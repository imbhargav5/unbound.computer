//! SQLite storage layer for the Armin session engine.
//!
//! SQLite is the ONLY durable store. All derived state is rebuilt from SQLite on recovery.
//!
//! # Design Principles
//!
//! - SQLite is the only source of truth
//! - Every write commits to SQLite first
//! - Crash = rebuild from SQLite
//! - No pluggable engines, no alternative backends

use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, Result as SqliteResult};
use std::path::Path;
use std::sync::Mutex;

use crate::types::{
    AgentStatus, CodingSessionRuntimeState, CodingSessionStatus, Message, MessageId, NewMessage,
    NewRepository, NewSession, NewSessionSecret, Repository, RepositoryId, RuntimeStatusEnvelope,
    Session, SessionId, SessionSecret, SessionState, SessionStatus, SessionUpdate, UserSetting,
    RUNTIME_STATUS_SCHEMA_VERSION,
};

/// Result of an atomic message insertion.
#[derive(Debug, Clone)]
pub struct InsertedMessage {
    pub id: MessageId,
    pub sequence_number: i64,
}

/// SQLite storage for sessions and messages.
///
/// Thread-safe via internal Mutex. All operations acquire the lock.
pub struct SqliteStore {
    conn: Mutex<Connection>,
}

impl SqliteStore {
    /// Opens a SQLite database at the given path.
    ///
    /// Creates the database and schema if they don't exist.
    pub fn open(path: impl AsRef<Path>) -> SqliteResult<Self> {
        let conn = Connection::open(path)?;
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.init_schema()?;
        Ok(store)
    }

    /// Creates an in-memory SQLite database.
    ///
    /// Useful for testing.
    pub fn in_memory() -> SqliteResult<Self> {
        let conn = Connection::open_in_memory()?;
        let store = Self {
            conn: Mutex::new(conn),
        };
        store.init_schema()?;
        Ok(store)
    }

    /// Initializes the database schema.
    ///
    /// This schema is compatible with the daemon-database migrations.
    /// Armin now manages the complete schema previously split across two databases.
    fn init_schema(&self) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");

        // Migrations tracking table
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            "#,
        )?;

        // Check if required tables exist (daemon-database may have already created them)
        let has_agent_sessions: bool = conn
            .query_row(
                "SELECT COUNT(*) > 0 FROM sqlite_master WHERE type='table' AND name='agent_coding_sessions'",
                [],
                |row| row.get(0),
            )
            .unwrap_or(false);

        if !has_agent_sessions {
            // Fresh database or incomplete schema - run full migration
            self.migrate_v1_full_schema(&conn)?;
        }

        self.ensure_session_agent_metadata_columns(&conn)?;

        // Ensure runtime session state uses grouped JSON envelope schema
        self.ensure_session_state_runtime_envelope(&conn)?;

        // Drop legacy outbox table if it exists
        conn.execute_batch("DROP TABLE IF EXISTS agent_coding_session_event_outbox;")?;

        Ok(())
    }

    /// Ensures session runtime state uses grouped JSON envelope storage.
    fn ensure_session_state_runtime_envelope(&self, conn: &Connection) -> SqliteResult<()> {
        let mut stmt = conn.prepare("PRAGMA table_info(agent_coding_session_state)")?;
        let columns: Vec<String> = stmt
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<Result<Vec<_>, _>>()?;

        let has_state_json = columns.iter().any(|c| c == "state_json");
        let has_updated_at_ms = columns.iter().any(|c| c == "updated_at_ms");
        let has_agent_status = columns.iter().any(|c| c == "agent_status");

        // Already in target shape.
        if has_state_json && has_updated_at_ms && !has_agent_status {
            return Ok(());
        }

        conn.execute_batch(
            r#"
            DROP TABLE IF EXISTS agent_coding_session_state_new;

            CREATE TABLE agent_coding_session_state_new (
                session_id TEXT PRIMARY KEY REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
                state_json TEXT NOT NULL,
                updated_at_ms INTEGER NOT NULL,
                CHECK (json_valid(state_json)),
                CHECK (json_extract(state_json, '$.schema_version') = 1),
                CHECK (json_type(state_json, '$.coding_session') = 'object'),
                CHECK (json_extract(state_json, '$.coding_session.status') IN ('running', 'idle', 'waiting', 'not-available', 'error')),
                CHECK (json_type(state_json, '$.device_id') = 'text'),
                CHECK (json_type(state_json, '$.session_id') = 'text'),
                CHECK (json_extract(state_json, '$.session_id') = session_id),
                CHECK (json_type(state_json, '$.updated_at_ms') IN ('integer', 'real')),
                CHECK (CAST(json_extract(state_json, '$.updated_at_ms') AS INTEGER) = updated_at_ms),
                CHECK (
                    json_type(state_json, '$.coding_session.error_message') IS NULL
                    OR json_type(state_json, '$.coding_session.error_message') = 'text'
                )
            );
            "#,
        )?;

        if columns.iter().any(|c| c == "session_id") {
            if has_agent_status {
                conn.execute_batch(
                    r#"
                    INSERT INTO agent_coding_session_state_new (session_id, state_json, updated_at_ms)
                    SELECT
                        session_id,
                        json_object(
                            'schema_version', 1,
                            'coding_session', json_object(
                                'status',
                                CASE lower(COALESCE(agent_status, 'idle'))
                                    WHEN 'running' THEN 'running'
                                    WHEN 'waiting' THEN 'waiting'
                                    WHEN 'error' THEN 'error'
                                    WHEN 'not-available' THEN 'not-available'
                                    ELSE 'idle'
                                END
                            ),
                            'device_id', '00000000-0000-0000-0000-000000000000',
                            'session_id', session_id,
                            'updated_at_ms',
                            COALESCE(
                                CAST(strftime('%s', updated_at) AS INTEGER) * 1000,
                                CAST(strftime('%s', 'now') AS INTEGER) * 1000
                            )
                        ),
                        COALESCE(
                            CAST(strftime('%s', updated_at) AS INTEGER) * 1000,
                            CAST(strftime('%s', 'now') AS INTEGER) * 1000
                        )
                    FROM agent_coding_session_state;
                    "#,
                )?;
            } else if has_state_json {
                conn.execute_batch(
                    r#"
                    INSERT INTO agent_coding_session_state_new (session_id, state_json, updated_at_ms)
                    SELECT
                        session_id,
                        json_object(
                            'schema_version', 1,
                            'coding_session', json_object(
                                'status',
                                CASE lower(COALESCE(json_extract(state_json, '$.coding_session.status'), 'idle'))
                                    WHEN 'running' THEN 'running'
                                    WHEN 'waiting' THEN 'waiting'
                                    WHEN 'error' THEN 'error'
                                    WHEN 'not-available' THEN 'not-available'
                                    ELSE 'idle'
                                END
                            ),
                            'device_id',
                            COALESCE(
                                NULLIF(json_extract(state_json, '$.device_id'), ''),
                                '00000000-0000-0000-0000-000000000000'
                            ),
                            'session_id', session_id,
                            'updated_at_ms',
                            COALESCE(
                                CAST(json_extract(state_json, '$.updated_at_ms') AS INTEGER),
                                CAST(strftime('%s', 'now') AS INTEGER) * 1000
                            )
                        ),
                        COALESCE(
                            CAST(json_extract(state_json, '$.updated_at_ms') AS INTEGER),
                            CAST(strftime('%s', 'now') AS INTEGER) * 1000
                        )
                    FROM agent_coding_session_state;
                    "#,
                )?;
            }
        }

        conn.execute_batch(
            r#"
            DROP TABLE IF EXISTS agent_coding_session_state;
            ALTER TABLE agent_coding_session_state_new RENAME TO agent_coding_session_state;
            "#,
        )?;

        Ok(())
    }

    /// V1: Complete schema for all Armin-managed entities.
    fn migrate_v1_full_schema(&self, conn: &Connection) -> SqliteResult<()> {
        tracing::info!("Applying Armin migration v1: full schema");

        // Repositories table
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS repositories (
                id TEXT PRIMARY KEY,
                path TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                last_accessed_at TEXT NOT NULL,
                added_at TEXT NOT NULL,
                is_git_repository INTEGER NOT NULL DEFAULT 0,
                sessions_path TEXT,
                default_branch TEXT,
                default_remote TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE INDEX IF NOT EXISTS idx_repositories_last_accessed_at
                ON repositories(last_accessed_at);
            CREATE INDEX IF NOT EXISTS idx_repositories_path
                ON repositories(path);
            "#,
        )?;

        // Agent coding sessions table (replaces simple 'sessions' table)
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS agent_coding_sessions (
                id TEXT PRIMARY KEY,
                repository_id TEXT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
                title TEXT NOT NULL DEFAULT 'New conversation',
                agent_id TEXT,
                agent_name TEXT,
                issue_id TEXT,
                issue_title TEXT,
                issue_url TEXT,
                claude_session_id TEXT,
                status TEXT NOT NULL DEFAULT 'active',
                is_worktree INTEGER NOT NULL DEFAULT 0,
                worktree_path TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                last_accessed_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE INDEX IF NOT EXISTS idx_sessions_repository_id
                ON agent_coding_sessions(repository_id);
            CREATE INDEX IF NOT EXISTS idx_sessions_status
                ON agent_coding_sessions(status);
            CREATE INDEX IF NOT EXISTS idx_sessions_last_accessed_at
                ON agent_coding_sessions(last_accessed_at);
            CREATE INDEX IF NOT EXISTS idx_sessions_is_worktree
                ON agent_coding_sessions(is_worktree);
            CREATE INDEX IF NOT EXISTS idx_sessions_agent_id
                ON agent_coding_sessions(agent_id);
            CREATE INDEX IF NOT EXISTS idx_sessions_issue_id
                ON agent_coding_sessions(issue_id);
            "#,
        )?;

        // Session state table
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS agent_coding_session_state (
                session_id TEXT PRIMARY KEY REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
                state_json TEXT NOT NULL,
                updated_at_ms INTEGER NOT NULL,
                CHECK (json_valid(state_json)),
                CHECK (json_extract(state_json, '$.schema_version') = 1),
                CHECK (json_type(state_json, '$.coding_session') = 'object'),
                CHECK (json_extract(state_json, '$.coding_session.status') IN ('running', 'idle', 'waiting', 'not-available', 'error')),
                CHECK (json_type(state_json, '$.device_id') = 'text'),
                CHECK (json_type(state_json, '$.session_id') = 'text'),
                CHECK (json_extract(state_json, '$.session_id') = session_id),
                CHECK (json_type(state_json, '$.updated_at_ms') IN ('integer', 'real')),
                CHECK (CAST(json_extract(state_json, '$.updated_at_ms') AS INTEGER) = updated_at_ms),
                CHECK (
                    json_type(state_json, '$.coding_session.error_message') IS NULL
                    OR json_type(state_json, '$.coding_session.error_message') = 'text'
                )
            );
            "#,
        )?;

        // Messages table (plaintext content)
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS agent_coding_session_messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
                content TEXT NOT NULL,
                timestamp TEXT NOT NULL DEFAULT (datetime('now')),
                is_streaming INTEGER NOT NULL DEFAULT 0,
                sequence_number INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE INDEX IF NOT EXISTS idx_messages_session_id
                ON agent_coding_session_messages(session_id);
            CREATE INDEX IF NOT EXISTS idx_messages_session_seq
                ON agent_coding_session_messages(session_id, sequence_number);
            CREATE INDEX IF NOT EXISTS idx_messages_timestamp
                ON agent_coding_session_messages(timestamp);
            "#,
        )?;

        // Session secrets table
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS session_secrets (
                session_id TEXT PRIMARY KEY REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
                encrypted_secret BLOB NOT NULL,
                nonce BLOB NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            "#,
        )?;

        // User settings table
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS user_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                value_type TEXT NOT NULL,
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            "#,
        )?;

        // Record migration as version 11 (matches daemon-database final version)
        // so daemon-database won't attempt redundant schema transforms later.
        conn.execute(
            "INSERT INTO migrations (version, name) VALUES (11, 'armin_full_schema')",
            [],
        )?;

        tracing::info!("Armin migration v1 applied successfully");
        Ok(())
    }

    fn ensure_session_agent_metadata_columns(&self, conn: &Connection) -> SqliteResult<()> {
        let mut stmt = conn.prepare("PRAGMA table_info(agent_coding_sessions)")?;
        let columns: Vec<String> = stmt
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<Result<Vec<_>, _>>()?;

        if !columns.iter().any(|c| c == "agent_id") {
            conn.execute_batch("ALTER TABLE agent_coding_sessions ADD COLUMN agent_id TEXT;")?;
        }

        if !columns.iter().any(|c| c == "agent_name") {
            conn.execute_batch("ALTER TABLE agent_coding_sessions ADD COLUMN agent_name TEXT;")?;
        }

        if !columns.iter().any(|c| c == "issue_id") {
            conn.execute_batch("ALTER TABLE agent_coding_sessions ADD COLUMN issue_id TEXT;")?;
        }

        if !columns.iter().any(|c| c == "issue_title") {
            conn.execute_batch("ALTER TABLE agent_coding_sessions ADD COLUMN issue_title TEXT;")?;
        }

        if !columns.iter().any(|c| c == "issue_url") {
            conn.execute_batch("ALTER TABLE agent_coding_sessions ADD COLUMN issue_url TEXT;")?;
        }

        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS idx_sessions_agent_id ON agent_coding_sessions(agent_id);
            CREATE INDEX IF NOT EXISTS idx_sessions_issue_id ON agent_coding_sessions(issue_id);
            ",
        )?;

        Ok(())
    }

    /// Returns the current time as an RFC3339 string.
    fn now_rfc3339() -> String {
        Utc::now().to_rfc3339()
    }

    const DEFAULT_RUNTIME_DEVICE_ID: &'static str = "00000000-0000-0000-0000-000000000000";

    fn now_timestamp_ms() -> i64 {
        Utc::now().timestamp_millis()
    }

    /// Parses an RFC3339 datetime string, falling back to current time on error.
    fn parse_datetime(s: String) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(&s)
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(|_| Utc::now())
    }

    fn parse_datetime_from_millis(ms: i64) -> DateTime<Utc> {
        DateTime::<Utc>::from_timestamp_millis(ms).unwrap_or_else(Utc::now)
    }

    // ========================================================================
    // Repository operations
    // ========================================================================

    /// Inserts a new repository.
    pub fn insert_repository(&self, repo: &NewRepository) -> SqliteResult<Repository> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        conn.execute(
            "INSERT INTO repositories (id, path, name, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?4, ?5, ?6, ?7, ?8, ?4, ?4)",
            params![
                repo.id.as_str(),
                repo.path,
                repo.name,
                now,
                repo.is_git_repository,
                repo.sessions_path,
                repo.default_branch,
                repo.default_remote,
            ],
        )?;
        drop(conn);
        self.get_repository(&repo.id)?
            .ok_or_else(|| rusqlite::Error::QueryReturnedNoRows)
    }

    /// Gets a repository by ID.
    pub fn get_repository(&self, id: &RepositoryId) -> SqliteResult<Option<Repository>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT id, path, name, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
             FROM repositories WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id.as_str()], |row| {
            Ok(Repository {
                id: RepositoryId::from_string(row.get::<_, String>(0)?),
                path: row.get(1)?,
                name: row.get(2)?,
                last_accessed_at: Self::parse_datetime(row.get::<_, String>(3)?),
                added_at: Self::parse_datetime(row.get::<_, String>(4)?),
                is_git_repository: row.get(5)?,
                sessions_path: row.get(6)?,
                default_branch: row.get(7)?,
                default_remote: row.get(8)?,
                created_at: Self::parse_datetime(row.get::<_, String>(9)?),
                updated_at: Self::parse_datetime(row.get::<_, String>(10)?),
            })
        });

        match result {
            Ok(repo) => Ok(Some(repo)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Gets a repository by path.
    pub fn get_repository_by_path(&self, path: &str) -> SqliteResult<Option<Repository>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT id, path, name, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
             FROM repositories WHERE path = ?1",
        )?;

        let result = stmt.query_row(params![path], |row| {
            Ok(Repository {
                id: RepositoryId::from_string(row.get::<_, String>(0)?),
                path: row.get(1)?,
                name: row.get(2)?,
                last_accessed_at: Self::parse_datetime(row.get::<_, String>(3)?),
                added_at: Self::parse_datetime(row.get::<_, String>(4)?),
                is_git_repository: row.get(5)?,
                sessions_path: row.get(6)?,
                default_branch: row.get(7)?,
                default_remote: row.get(8)?,
                created_at: Self::parse_datetime(row.get::<_, String>(9)?),
                updated_at: Self::parse_datetime(row.get::<_, String>(10)?),
            })
        });

        match result {
            Ok(repo) => Ok(Some(repo)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Lists all repositories ordered by last accessed.
    pub fn list_repositories(&self) -> SqliteResult<Vec<Repository>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT id, path, name, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
             FROM repositories ORDER BY last_accessed_at DESC",
        )?;

        let repos = stmt
            .query_map([], |row| {
                Ok(Repository {
                    id: RepositoryId::from_string(row.get::<_, String>(0)?),
                    path: row.get(1)?,
                    name: row.get(2)?,
                    last_accessed_at: Self::parse_datetime(row.get::<_, String>(3)?),
                    added_at: Self::parse_datetime(row.get::<_, String>(4)?),
                    is_git_repository: row.get(5)?,
                    sessions_path: row.get(6)?,
                    default_branch: row.get(7)?,
                    default_remote: row.get(8)?,
                    created_at: Self::parse_datetime(row.get::<_, String>(9)?),
                    updated_at: Self::parse_datetime(row.get::<_, String>(10)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(repos)
    }

    /// Deletes a repository by ID.
    pub fn delete_repository(&self, id: &RepositoryId) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let count = conn.execute(
            "DELETE FROM repositories WHERE id = ?1",
            params![id.as_str()],
        )?;
        Ok(count > 0)
    }

    /// Updates repository settings.
    pub fn update_repository_settings(
        &self,
        id: &RepositoryId,
        sessions_path: Option<String>,
        default_branch: Option<String>,
        default_remote: Option<String>,
    ) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        let count = conn.execute(
            "UPDATE repositories
             SET sessions_path = ?1, default_branch = ?2, default_remote = ?3, updated_at = ?4
             WHERE id = ?5",
            params![
                sessions_path,
                default_branch,
                default_remote,
                now,
                id.as_str()
            ],
        )?;
        Ok(count > 0)
    }

    // ========================================================================
    // Agent coding session operations (full metadata)
    // ========================================================================

    /// Inserts a new session with full metadata.
    pub fn insert_agent_session(&self, session: &NewSession) -> SqliteResult<Session> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        conn.execute(
            "INSERT INTO agent_coding_sessions (id, repository_id, title, agent_id, agent_name, issue_id, issue_title, issue_url, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'active', ?10, ?11, ?12, ?12, ?12)",
            params![
                session.id.as_str(),
                session.repository_id.as_str(),
                session.title,
                session.agent_id,
                session.agent_name,
                session.issue_id,
                session.issue_title,
                session.issue_url,
                session.claude_session_id,
                session.is_worktree,
                session.worktree_path,
                now,
            ],
        )?;
        drop(conn);
        self.get_agent_session(&session.id)?
            .ok_or_else(|| rusqlite::Error::QueryReturnedNoRows)
    }

    /// Gets a session by ID.
    pub fn get_agent_session(&self, id: &SessionId) -> SqliteResult<Option<Session>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT id, repository_id, title, agent_id, agent_name, issue_id, issue_title, issue_url, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
             FROM agent_coding_sessions WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id.as_str()], |row| {
            Ok(Session {
                id: SessionId::from_string(row.get::<_, String>(0)?),
                repository_id: RepositoryId::from_string(row.get::<_, String>(1)?),
                title: row.get(2)?,
                agent_id: row.get(3)?,
                agent_name: row.get(4)?,
                issue_id: row.get(5)?,
                issue_title: row.get(6)?,
                issue_url: row.get(7)?,
                claude_session_id: row.get(8)?,
                status: SessionStatus::from_str(&row.get::<_, String>(9)?),
                is_worktree: row.get(10)?,
                worktree_path: row.get(11)?,
                created_at: Self::parse_datetime(row.get::<_, String>(12)?),
                last_accessed_at: Self::parse_datetime(row.get::<_, String>(13)?),
                updated_at: Self::parse_datetime(row.get::<_, String>(14)?),
            })
        });

        match result {
            Ok(session) => Ok(Some(session)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Lists sessions for a repository.
    pub fn list_agent_sessions_for_repository(
        &self,
        repository_id: &RepositoryId,
    ) -> SqliteResult<Vec<Session>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT id, repository_id, title, agent_id, agent_name, issue_id, issue_title, issue_url, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
             FROM agent_coding_sessions WHERE repository_id = ?1 ORDER BY last_accessed_at DESC",
        )?;

        let sessions = stmt
            .query_map(params![repository_id.as_str()], |row| {
                Ok(Session {
                    id: SessionId::from_string(row.get::<_, String>(0)?),
                    repository_id: RepositoryId::from_string(row.get::<_, String>(1)?),
                    title: row.get(2)?,
                    agent_id: row.get(3)?,
                    agent_name: row.get(4)?,
                    issue_id: row.get(5)?,
                    issue_title: row.get(6)?,
                    issue_url: row.get(7)?,
                    claude_session_id: row.get(8)?,
                    status: SessionStatus::from_str(&row.get::<_, String>(9)?),
                    is_worktree: row.get(10)?,
                    worktree_path: row.get(11)?,
                    created_at: Self::parse_datetime(row.get::<_, String>(12)?),
                    last_accessed_at: Self::parse_datetime(row.get::<_, String>(13)?),
                    updated_at: Self::parse_datetime(row.get::<_, String>(14)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(sessions)
    }

    /// Lists all agent sessions (for recovery).
    pub fn list_all_agent_sessions(&self) -> SqliteResult<Vec<Session>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT id, repository_id, title, agent_id, agent_name, issue_id, issue_title, issue_url, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
             FROM agent_coding_sessions ORDER BY last_accessed_at DESC",
        )?;

        let sessions = stmt
            .query_map([], |row| {
                Ok(Session {
                    id: SessionId::from_string(row.get::<_, String>(0)?),
                    repository_id: RepositoryId::from_string(row.get::<_, String>(1)?),
                    title: row.get(2)?,
                    agent_id: row.get(3)?,
                    agent_name: row.get(4)?,
                    issue_id: row.get(5)?,
                    issue_title: row.get(6)?,
                    issue_url: row.get(7)?,
                    claude_session_id: row.get(8)?,
                    status: SessionStatus::from_str(&row.get::<_, String>(9)?),
                    is_worktree: row.get(10)?,
                    worktree_path: row.get(11)?,
                    created_at: Self::parse_datetime(row.get::<_, String>(12)?),
                    last_accessed_at: Self::parse_datetime(row.get::<_, String>(13)?),
                    updated_at: Self::parse_datetime(row.get::<_, String>(14)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(sessions)
    }

    /// Updates a session with partial fields.
    pub fn update_agent_session(
        &self,
        id: &SessionId,
        update: &SessionUpdate,
    ) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();

        let mut updates = vec!["updated_at = ?1".to_string()];
        let mut param_index = 2;

        if update.title.is_some() {
            updates.push(format!("title = ?{}", param_index));
            param_index += 1;
        }
        if update.claude_session_id.is_some() {
            updates.push(format!("claude_session_id = ?{}", param_index));
            param_index += 1;
        }
        if update.status.is_some() {
            updates.push(format!("status = ?{}", param_index));
            param_index += 1;
        }
        if update.last_accessed_at.is_some() {
            updates.push(format!("last_accessed_at = ?{}", param_index));
            param_index += 1;
        }

        let sql = format!(
            "UPDATE agent_coding_sessions SET {} WHERE id = ?{}",
            updates.join(", "),
            param_index
        );

        // Build params dynamically
        let mut params_vec: Vec<Box<dyn rusqlite::ToSql>> = vec![Box::new(now)];
        if let Some(ref title) = update.title {
            params_vec.push(Box::new(title.clone()));
        }
        if let Some(ref claude_id) = update.claude_session_id {
            params_vec.push(Box::new(claude_id.clone()));
        }
        if let Some(status) = update.status {
            params_vec.push(Box::new(status.as_str().to_string()));
        }
        if let Some(last_accessed) = update.last_accessed_at {
            params_vec.push(Box::new(last_accessed.to_rfc3339()));
        }
        params_vec.push(Box::new(id.as_str().to_string()));

        let params_refs: Vec<&dyn rusqlite::ToSql> =
            params_vec.iter().map(|p| p.as_ref()).collect();
        let count = conn.execute(&sql, params_refs.as_slice())?;
        Ok(count > 0)
    }

    /// Updates the Claude session ID for a session.
    pub fn update_agent_session_claude_id(
        &self,
        id: &SessionId,
        claude_session_id: &str,
    ) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        let count = conn.execute(
            "UPDATE agent_coding_sessions SET claude_session_id = ?1, updated_at = ?2 WHERE id = ?3",
            params![claude_session_id, now, id.as_str()],
        )?;
        Ok(count > 0)
    }

    /// Updates session last accessed time.
    #[allow(dead_code)]
    pub fn touch_agent_session(&self, id: &SessionId) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        let count = conn.execute(
            "UPDATE agent_coding_sessions SET last_accessed_at = ?1, updated_at = ?1 WHERE id = ?2",
            params![now, id.as_str()],
        )?;
        Ok(count > 0)
    }

    /// Deletes an agent session by ID.
    pub fn delete_agent_session(&self, id: &SessionId) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let count = conn.execute(
            "DELETE FROM agent_coding_sessions WHERE id = ?1",
            params![id.as_str()],
        )?;
        Ok(count > 0)
    }

    /// Checks if an agent session exists.
    #[allow(dead_code)]
    pub fn agent_session_exists(&self, id: &SessionId) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM agent_coding_sessions WHERE id = ?1",
            params![id.as_str()],
            |row| row.get(0),
        )?;
        Ok(count > 0)
    }

    // ========================================================================
    // Session state operations
    // ========================================================================

    /// Gets or creates session state.
    pub fn get_or_create_session_state(
        &self,
        session_id: &SessionId,
    ) -> SqliteResult<SessionState> {
        if let Some(state) = self.get_session_state(session_id)? {
            return Ok(state);
        }

        let conn = self.conn.lock().expect("lock poisoned");
        let now_ms = Self::now_timestamp_ms();
        conn.execute(
            "INSERT INTO agent_coding_session_state (session_id, state_json, updated_at_ms)
             VALUES (
                ?1,
                json_object(
                    'schema_version', ?4,
                    'coding_session', json_object('status', 'idle'),
                    'device_id', ?2,
                    'session_id', ?1,
                    'updated_at_ms', ?3
                ),
                ?3
             )",
            params![
                session_id.as_str(),
                Self::DEFAULT_RUNTIME_DEVICE_ID,
                now_ms,
                RUNTIME_STATUS_SCHEMA_VERSION
            ],
        )?;
        drop(conn);

        self.get_session_state(session_id)?
            .ok_or_else(|| rusqlite::Error::QueryReturnedNoRows)
    }

    /// Gets session state.
    pub fn get_session_state(&self, session_id: &SessionId) -> SqliteResult<Option<SessionState>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT
                session_id,
                json_extract(state_json, '$.coding_session.status') AS coding_session_status,
                json_extract(state_json, '$.coding_session.error_message') AS error_message,
                json_extract(state_json, '$.device_id') AS device_id,
                updated_at_ms
             FROM agent_coding_session_state WHERE session_id = ?1",
        )?;

        let result = stmt.query_row(params![session_id.as_str()], |row| {
            let session_id = SessionId::from_string(row.get::<_, String>(0)?);
            let raw_status: Option<String> = row.get(1)?;
            let error_message: Option<String> = row.get(2)?;
            let device_id: Option<String> = row.get(3)?;
            let updated_at_ms: i64 = row.get(4)?;
            let status = CodingSessionStatus::from_str(raw_status.as_deref().unwrap_or("idle"));

            let runtime_status = RuntimeStatusEnvelope {
                schema_version: RUNTIME_STATUS_SCHEMA_VERSION,
                coding_session: CodingSessionRuntimeState {
                    status,
                    error_message,
                },
                device_id: device_id.unwrap_or_else(|| Self::DEFAULT_RUNTIME_DEVICE_ID.to_string()),
                session_id: session_id.clone(),
                updated_at_ms,
            };

            Ok(SessionState {
                session_id,
                runtime_status,
                updated_at: Self::parse_datetime_from_millis(updated_at_ms),
            })
        });

        match result {
            Ok(state) => Ok(Some(state)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Updates the canonical runtime status envelope.
    pub fn update_runtime_status(
        &self,
        session_id: &SessionId,
        device_id: &str,
        status: CodingSessionStatus,
        error_message: Option<String>,
    ) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now_ms = Self::now_timestamp_ms();
        let count = if let Some(error_message) = error_message {
            conn.execute(
                "UPDATE agent_coding_session_state
                 SET
                    state_json = json_set(
                        COALESCE(
                            state_json,
                            json_object(
                                'schema_version', ?5,
                                'coding_session', json_object('status', 'idle'),
                                'device_id', ?2,
                                'session_id', ?1,
                                'updated_at_ms', ?3
                            )
                        ),
                        '$.schema_version', ?5,
                        '$.coding_session.status', ?4,
                        '$.coding_session.error_message', ?6,
                        '$.device_id', ?2,
                        '$.session_id', ?1,
                        '$.updated_at_ms', ?3
                    ),
                    updated_at_ms = ?3
                 WHERE session_id = ?1",
                params![
                    session_id.as_str(),
                    device_id,
                    now_ms,
                    status.as_str(),
                    RUNTIME_STATUS_SCHEMA_VERSION,
                    error_message
                ],
            )?
        } else {
            conn.execute(
                "UPDATE agent_coding_session_state
                 SET
                    state_json = json_remove(
                        json_set(
                            COALESCE(
                                state_json,
                                json_object(
                                    'schema_version', ?5,
                                    'coding_session', json_object('status', 'idle'),
                                    'device_id', ?2,
                                    'session_id', ?1,
                                    'updated_at_ms', ?3
                                )
                            ),
                            '$.schema_version', ?5,
                            '$.coding_session.status', ?4,
                            '$.device_id', ?2,
                            '$.session_id', ?1,
                            '$.updated_at_ms', ?3
                        ),
                        '$.coding_session.error_message'
                    ),
                    updated_at_ms = ?3
                 WHERE session_id = ?1",
                params![
                    session_id.as_str(),
                    device_id,
                    now_ms,
                    status.as_str(),
                    RUNTIME_STATUS_SCHEMA_VERSION
                ],
            )?
        };

        Ok(count > 0)
    }

    /// Legacy scalar status writer kept during migration.
    #[allow(dead_code)]
    pub fn update_agent_status(
        &self,
        session_id: &SessionId,
        status: AgentStatus,
    ) -> SqliteResult<bool> {
        self.update_runtime_status(session_id, Self::DEFAULT_RUNTIME_DEVICE_ID, status, None)
    }

    // ========================================================================
    // Agent message operations (new table)
    // ========================================================================

    /// Inserts a message into the agent messages table with atomic sequence assignment.
    pub fn insert_agent_message(
        &self,
        session: &SessionId,
        msg: &NewMessage,
    ) -> SqliteResult<InsertedMessage> {
        let id = MessageId::new();
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();

        // Atomic insert with sequence number computed in subquery
        let mut stmt = conn.prepare(
            r#"
            INSERT INTO agent_coding_session_messages (id, session_id, content, timestamp, is_streaming, sequence_number, created_at)
            VALUES (?1, ?2, ?3, ?4, 0,
                (SELECT COALESCE(MAX(sequence_number), 0) + 1 FROM agent_coding_session_messages WHERE session_id = ?2),
                ?4)
            RETURNING sequence_number
            "#,
        )?;

        let sequence_number: i64 = stmt.query_row(
            params![id.as_str(), session.as_str(), msg.content, now],
            |row| row.get(0),
        )?;

        Ok(InsertedMessage {
            id,
            sequence_number,
        })
    }

    /// Gets all messages for a session from the agent messages table.
    pub fn get_agent_messages(&self, session: &SessionId) -> SqliteResult<Vec<Message>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare(
            "SELECT id, content, sequence_number FROM agent_coding_session_messages WHERE session_id = ? ORDER BY sequence_number",
        )?;
        let rows = stmt.query_map(params![session.as_str()], |row| {
            let id = MessageId::from_string(row.get::<_, String>(0)?);
            let content: String = row.get(1)?;
            let sequence_number: i64 = row.get(2)?;
            Ok(Message {
                id,
                content,
                sequence_number,
            })
        })?;

        let mut messages = Vec::new();
        for row in rows {
            messages.push(row?);
        }
        Ok(messages)
    }

    // ========================================================================
    // Session secrets operations
    // ========================================================================

    /// Gets a session secret by session ID.
    pub fn get_session_secret(
        &self,
        session_id: &SessionId,
    ) -> SqliteResult<Option<SessionSecret>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT session_id, encrypted_secret, nonce, created_at
             FROM session_secrets WHERE session_id = ?1",
        )?;

        let result = stmt.query_row(params![session_id.as_str()], |row| {
            Ok(SessionSecret {
                session_id: SessionId::from_string(row.get::<_, String>(0)?),
                encrypted_secret: row.get(1)?,
                nonce: row.get(2)?,
                created_at: Self::parse_datetime(row.get::<_, String>(3)?),
            })
        });

        match result {
            Ok(secret) => Ok(Some(secret)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Stores a session secret (upsert).
    pub fn set_session_secret(&self, secret: &NewSessionSecret) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        conn.execute(
            "INSERT INTO session_secrets (session_id, encrypted_secret, nonce, created_at)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(session_id) DO UPDATE SET encrypted_secret = ?2, nonce = ?3",
            params![
                secret.session_id.as_str(),
                secret.encrypted_secret,
                secret.nonce,
                now
            ],
        )?;
        Ok(())
    }

    /// Deletes a session secret.
    pub fn delete_session_secret(&self, session_id: &SessionId) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let count = conn.execute(
            "DELETE FROM session_secrets WHERE session_id = ?1",
            params![session_id.as_str()],
        )?;
        Ok(count > 0)
    }

    /// Checks if a session secret exists.
    pub fn has_session_secret(&self, session_id: &SessionId) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM session_secrets WHERE session_id = ?1",
            params![session_id.as_str()],
            |row| row.get(0),
        )?;
        Ok(count > 0)
    }

    // ========================================================================
    // User settings operations
    // ========================================================================

    /// Gets a user setting.
    #[allow(dead_code)]
    pub fn get_setting(&self, key: &str) -> SqliteResult<Option<UserSetting>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare(
            "SELECT key, value, value_type, updated_at FROM user_settings WHERE key = ?1",
        )?;

        let result = stmt.query_row(params![key], |row| {
            Ok(UserSetting {
                key: row.get(0)?,
                value: row.get(1)?,
                value_type: row.get(2)?,
                updated_at: Self::parse_datetime(row.get::<_, String>(3)?),
            })
        });

        match result {
            Ok(setting) => Ok(Some(setting)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Sets a user setting.
    #[allow(dead_code)]
    pub fn set_setting(&self, key: &str, value: &str, value_type: &str) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        conn.execute(
            "INSERT INTO user_settings (key, value, value_type, updated_at)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(key) DO UPDATE SET value = ?2, value_type = ?3, updated_at = ?4",
            params![key, value, value_type, now],
        )?;
        Ok(())
    }

    /// Deletes a user setting.
    #[allow(dead_code)]
    pub fn delete_setting(&self, key: &str) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let count = conn.execute("DELETE FROM user_settings WHERE key = ?1", params![key])?;
        Ok(count > 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_repo(store: &SqliteStore) -> RepositoryId {
        let repo = NewRepository {
            id: RepositoryId::new(),
            path: "/tmp/test".to_string(),
            name: "Test".to_string(),
            is_git_repository: false,
            sessions_path: None,
            default_branch: None,
            default_remote: None,
        };
        store.insert_repository(&repo).unwrap();
        repo.id
    }

    fn create_test_session(store: &SqliteStore, repo_id: &RepositoryId) -> SessionId {
        let session = NewSession {
            id: SessionId::new(),
            repository_id: repo_id.clone(),
            title: "Test".to_string(),
            agent_id: None,
            agent_name: None,
            issue_id: None,
            issue_title: None,
            issue_url: None,
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        };
        store.insert_agent_session(&session).unwrap();
        session.id
    }

    #[test]
    fn create_and_get_session() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let session_id = create_test_session(&store, &repo_id);

        let session = store.get_agent_session(&session_id).unwrap().unwrap();
        assert_eq!(session.id, session_id);
        assert_eq!(session.status, SessionStatus::Active);
    }

    #[test]
    fn create_session_with_specific_id() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let id = SessionId::from_string("my-custom-session-id");

        let session = NewSession {
            id: id.clone(),
            repository_id: repo_id,
            title: "Test".to_string(),
            agent_id: Some("agent-123".to_string()),
            agent_name: Some("Debug Agent".to_string()),
            issue_id: Some("ENG-123".to_string()),
            issue_title: Some("Fix launch bug".to_string()),
            issue_url: Some("https://example.com/issues/ENG-123".to_string()),
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        };
        store.insert_agent_session(&session).unwrap();

        let retrieved = store.get_agent_session(&id).unwrap().unwrap();
        assert_eq!(retrieved.id.as_str(), "my-custom-session-id");
        assert_eq!(retrieved.agent_id.as_deref(), Some("agent-123"));
        assert_eq!(retrieved.agent_name.as_deref(), Some("Debug Agent"));
        assert_eq!(retrieved.issue_id.as_deref(), Some("ENG-123"));
        assert_eq!(retrieved.issue_title.as_deref(), Some("Fix launch bug"));
        assert_eq!(
            retrieved.issue_url.as_deref(),
            Some("https://example.com/issues/ENG-123")
        );
    }

    #[test]
    fn session_state_runtime_envelope_lifecycle() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let session_id = create_test_session(&store, &repo_id);

        let state = store.get_or_create_session_state(&session_id).unwrap();
        assert_eq!(
            state.runtime_status.coding_session.status,
            CodingSessionStatus::Idle
        );
        assert!(state.runtime_status.coding_session.error_message.is_none());

        assert!(store
            .update_runtime_status(
                &session_id,
                "device-running",
                CodingSessionStatus::Running,
                None,
            )
            .unwrap());
        let running = store.get_session_state(&session_id).unwrap().unwrap();
        assert_eq!(
            running.runtime_status.coding_session.status,
            CodingSessionStatus::Running
        );
        assert_eq!(running.runtime_status.device_id, "device-running");

        assert!(store
            .update_runtime_status(
                &session_id,
                "device-running",
                CodingSessionStatus::Waiting,
                Some("waiting on user".to_string()),
            )
            .unwrap());
        let waiting = store.get_session_state(&session_id).unwrap().unwrap();
        assert_eq!(
            waiting.runtime_status.coding_session.status,
            CodingSessionStatus::Waiting
        );
        assert_eq!(
            waiting
                .runtime_status
                .coding_session
                .error_message
                .as_deref(),
            Some("waiting on user")
        );
    }

    #[test]
    fn session_state_schema_uses_json_blob() {
        let store = SqliteStore::in_memory().unwrap();
        let conn = store.conn.lock().expect("lock poisoned");

        let columns: Vec<String> = conn
            .prepare("PRAGMA table_info(agent_coding_session_state)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();

        assert!(columns.contains(&"state_json".to_string()));
        assert!(columns.contains(&"updated_at_ms".to_string()));
        assert!(!columns.contains(&"agent_status".to_string()));
    }

    #[test]
    fn update_repository_settings_roundtrip() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);

        assert!(store
            .update_repository_settings(
                &repo_id,
                Some("/tmp/sessions".to_string()),
                Some("main".to_string()),
                Some("origin".to_string()),
            )
            .unwrap());

        let updated = store.get_repository(&repo_id).unwrap().unwrap();
        assert_eq!(updated.sessions_path, Some("/tmp/sessions".to_string()));
        assert_eq!(updated.default_branch, Some("main".to_string()));
        assert_eq!(updated.default_remote, Some("origin".to_string()));

        assert!(store
            .update_repository_settings(&repo_id, None, None, None)
            .unwrap());
        let cleared = store.get_repository(&repo_id).unwrap().unwrap();
        assert_eq!(cleared.sessions_path, None);
        assert_eq!(cleared.default_branch, None);
        assert_eq!(cleared.default_remote, None);
    }

    #[test]
    fn close_session() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let session_id = create_test_session(&store, &repo_id);

        assert!(store.agent_session_exists(&session_id).unwrap());

        // Archive the session (equivalent to closing)
        let update = SessionUpdate {
            title: None,
            status: Some(SessionStatus::Archived),
            claude_session_id: None,
            last_accessed_at: None,
        };
        store.update_agent_session(&session_id, &update).unwrap();

        let session = store.get_agent_session(&session_id).unwrap().unwrap();
        assert_eq!(session.status, SessionStatus::Archived);
    }

    #[test]
    fn insert_and_get_messages() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let session_id = create_test_session(&store, &repo_id);

        let msg1 = NewMessage {
            content: "Hello".to_string(),
        };
        let msg2 = NewMessage {
            content: "Hi there!".to_string(),
        };

        let inserted1 = store.insert_agent_message(&session_id, &msg1).unwrap();
        let inserted2 = store.insert_agent_message(&session_id, &msg2).unwrap();

        // Verify atomic sequence assignment
        assert_eq!(inserted1.sequence_number, 1);
        assert_eq!(inserted2.sequence_number, 2);

        let messages = store.get_agent_messages(&session_id).unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].id, inserted1.id);
        assert_eq!(messages[0].content, "Hello");
        assert_eq!(messages[0].sequence_number, 1);
        assert_eq!(messages[1].id, inserted2.id);
        assert_eq!(messages[1].content, "Hi there!");
        assert_eq!(messages[1].sequence_number, 2);
    }

    #[test]
    fn message_count() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let session_id = create_test_session(&store, &repo_id);

        let messages = store.get_agent_messages(&session_id).unwrap();
        assert_eq!(messages.len(), 0);

        store
            .insert_agent_message(
                &session_id,
                &NewMessage {
                    content: "Test".to_string(),
                },
            )
            .unwrap();

        let messages = store.get_agent_messages(&session_id).unwrap();
        assert_eq!(messages.len(), 1);
    }

    #[test]
    fn atomic_sequence_assignment() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let session_id = create_test_session(&store, &repo_id);

        // First message should get sequence 1
        let inserted1 = store
            .insert_agent_message(
                &session_id,
                &NewMessage {
                    content: "First".to_string(),
                },
            )
            .unwrap();
        assert_eq!(inserted1.sequence_number, 1);

        // Second message should get sequence 2
        let inserted2 = store
            .insert_agent_message(
                &session_id,
                &NewMessage {
                    content: "Second".to_string(),
                },
            )
            .unwrap();
        assert_eq!(inserted2.sequence_number, 2);

        // Third message should get sequence 3
        let inserted3 = store
            .insert_agent_message(
                &session_id,
                &NewMessage {
                    content: "Third".to_string(),
                },
            )
            .unwrap();
        assert_eq!(inserted3.sequence_number, 3);
    }

    #[test]
    fn sequence_is_per_session() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let session1 = create_test_session(&store, &repo_id);
        let session2 = create_test_session(&store, &repo_id);

        // Each session has independent sequence numbers
        let msg1 = store
            .insert_agent_message(
                &session1,
                &NewMessage {
                    content: "S1-M1".to_string(),
                },
            )
            .unwrap();
        let msg2 = store
            .insert_agent_message(
                &session2,
                &NewMessage {
                    content: "S2-M1".to_string(),
                },
            )
            .unwrap();
        let msg3 = store
            .insert_agent_message(
                &session1,
                &NewMessage {
                    content: "S1-M2".to_string(),
                },
            )
            .unwrap();

        assert_eq!(msg1.sequence_number, 1); // session1 starts at 1
        assert_eq!(msg2.sequence_number, 1); // session2 starts at 1
        assert_eq!(msg3.sequence_number, 2); // session1 continues to 2
    }
}
