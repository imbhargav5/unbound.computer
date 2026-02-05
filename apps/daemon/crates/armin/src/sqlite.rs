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
    AgentStatus, Message, MessageId, NewMessage, NewOutboxEvent, NewRepository, NewSession,
    NewSessionSecret, OutboxEvent, OutboxStatus, Repository, RepositoryId, Session, SessionId,
    SessionSecret, SessionState, SessionStatus, SessionUpdate, UserSetting,
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

        // Ensure Supabase message outbox table exists for existing databases
        self.ensure_supabase_message_outbox(&conn)?;

        Ok(())
    }

    fn ensure_supabase_message_outbox(&self, conn: &Connection) -> SqliteResult<()> {
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS agent_coding_session_message_supabase_outbox (
                message_id TEXT PRIMARY KEY REFERENCES agent_coding_session_messages(id) ON DELETE CASCADE,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                sent_at TEXT,
                last_attempt_at TEXT,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_supabase_outbox_sent_at
                ON agent_coding_session_message_supabase_outbox(sent_at);
            CREATE INDEX IF NOT EXISTS idx_supabase_outbox_last_attempt_at
                ON agent_coding_session_message_supabase_outbox(last_attempt_at);
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
            "#,
        )?;

        // Session state table
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS agent_coding_session_state (
                session_id TEXT PRIMARY KEY REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
                agent_status TEXT NOT NULL DEFAULT 'idle',
                queued_commands TEXT,
                diff_summary TEXT,
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
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

        // Event outbox table
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS agent_coding_session_event_outbox (
                event_id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
                sequence_number INTEGER NOT NULL,
                relay_send_batch_id TEXT,
                message_id TEXT NOT NULL REFERENCES agent_coding_session_messages(id) ON DELETE CASCADE,
                status TEXT NOT NULL DEFAULT 'pending',
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                sent_at TEXT,
                acked_at TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_outbox_session_seq
                ON agent_coding_session_event_outbox(session_id, sequence_number);
            CREATE INDEX IF NOT EXISTS idx_outbox_status
                ON agent_coding_session_event_outbox(status);
            CREATE INDEX IF NOT EXISTS idx_outbox_batch_id
                ON agent_coding_session_event_outbox(relay_send_batch_id);
            CREATE INDEX IF NOT EXISTS idx_outbox_message_id
                ON agent_coding_session_event_outbox(message_id);
            CREATE UNIQUE INDEX IF NOT EXISTS idx_outbox_session_seq_unique
                ON agent_coding_session_event_outbox(session_id, sequence_number);

            CREATE TRIGGER IF NOT EXISTS cleanup_acked_events
            AFTER INSERT ON agent_coding_session_event_outbox
            BEGIN
                DELETE FROM agent_coding_session_event_outbox
                WHERE status = 'acked' AND acked_at < datetime('now', '-1 day');
            END;
            "#,
        )?;

        // Supabase message outbox table
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS agent_coding_session_message_supabase_outbox (
                message_id TEXT PRIMARY KEY REFERENCES agent_coding_session_messages(id) ON DELETE CASCADE,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                sent_at TEXT,
                last_attempt_at TEXT,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_supabase_outbox_sent_at
                ON agent_coding_session_message_supabase_outbox(sent_at);
            CREATE INDEX IF NOT EXISTS idx_supabase_outbox_last_attempt_at
                ON agent_coding_session_message_supabase_outbox(last_attempt_at);
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

        // Record migration as version 8 (matches daemon-database final version)
        // This prevents daemon-database from trying to apply its migrations
        // which expect the old encrypted schema
        conn.execute(
            "INSERT INTO migrations (version, name) VALUES (8, 'armin_full_schema')",
            [],
        )?;

        tracing::info!("Armin migration v1 applied successfully");
        Ok(())
    }

    /// Returns the current time as an RFC3339 string.
    fn now_rfc3339() -> String {
        Utc::now().to_rfc3339()
    }

    /// Parses an RFC3339 datetime string, falling back to current time on error.
    fn parse_datetime(s: String) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(&s)
            .map(|dt| dt.with_timezone(&Utc))
            .unwrap_or_else(|_| Utc::now())
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
        let count = conn.execute("DELETE FROM repositories WHERE id = ?1", params![id.as_str()])?;
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
            "INSERT INTO agent_coding_sessions (id, repository_id, title, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, 'active', ?5, ?6, ?7, ?7, ?7)",
            params![
                session.id.as_str(),
                session.repository_id.as_str(),
                session.title,
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
            "SELECT id, repository_id, title, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
             FROM agent_coding_sessions WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id.as_str()], |row| {
            Ok(Session {
                id: SessionId::from_string(row.get::<_, String>(0)?),
                repository_id: RepositoryId::from_string(row.get::<_, String>(1)?),
                title: row.get(2)?,
                claude_session_id: row.get(3)?,
                status: SessionStatus::from_str(&row.get::<_, String>(4)?),
                is_worktree: row.get(5)?,
                worktree_path: row.get(6)?,
                created_at: Self::parse_datetime(row.get::<_, String>(7)?),
                last_accessed_at: Self::parse_datetime(row.get::<_, String>(8)?),
                updated_at: Self::parse_datetime(row.get::<_, String>(9)?),
            })
        });

        match result {
            Ok(session) => Ok(Some(session)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Lists sessions for a repository.
    pub fn list_agent_sessions_for_repository(&self, repository_id: &RepositoryId) -> SqliteResult<Vec<Session>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT id, repository_id, title, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
             FROM agent_coding_sessions WHERE repository_id = ?1 ORDER BY last_accessed_at DESC",
        )?;

        let sessions = stmt
            .query_map(params![repository_id.as_str()], |row| {
                Ok(Session {
                    id: SessionId::from_string(row.get::<_, String>(0)?),
                    repository_id: RepositoryId::from_string(row.get::<_, String>(1)?),
                    title: row.get(2)?,
                    claude_session_id: row.get(3)?,
                    status: SessionStatus::from_str(&row.get::<_, String>(4)?),
                    is_worktree: row.get(5)?,
                    worktree_path: row.get(6)?,
                    created_at: Self::parse_datetime(row.get::<_, String>(7)?),
                    last_accessed_at: Self::parse_datetime(row.get::<_, String>(8)?),
                    updated_at: Self::parse_datetime(row.get::<_, String>(9)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(sessions)
    }

    /// Lists all agent sessions (for recovery).
    pub fn list_all_agent_sessions(&self) -> SqliteResult<Vec<Session>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT id, repository_id, title, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
             FROM agent_coding_sessions ORDER BY last_accessed_at DESC",
        )?;

        let sessions = stmt
            .query_map([], |row| {
                Ok(Session {
                    id: SessionId::from_string(row.get::<_, String>(0)?),
                    repository_id: RepositoryId::from_string(row.get::<_, String>(1)?),
                    title: row.get(2)?,
                    claude_session_id: row.get(3)?,
                    status: SessionStatus::from_str(&row.get::<_, String>(4)?),
                    is_worktree: row.get(5)?,
                    worktree_path: row.get(6)?,
                    created_at: Self::parse_datetime(row.get::<_, String>(7)?),
                    last_accessed_at: Self::parse_datetime(row.get::<_, String>(8)?),
                    updated_at: Self::parse_datetime(row.get::<_, String>(9)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(sessions)
    }

    /// Updates a session with partial fields.
    pub fn update_agent_session(&self, id: &SessionId, update: &SessionUpdate) -> SqliteResult<bool> {
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

        let params_refs: Vec<&dyn rusqlite::ToSql> = params_vec.iter().map(|p| p.as_ref()).collect();
        let count = conn.execute(&sql, params_refs.as_slice())?;
        Ok(count > 0)
    }

    /// Updates the Claude session ID for a session.
    pub fn update_agent_session_claude_id(&self, id: &SessionId, claude_session_id: &str) -> SqliteResult<bool> {
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
    pub fn get_or_create_session_state(&self, session_id: &SessionId) -> SqliteResult<SessionState> {
        if let Some(state) = self.get_session_state(session_id)? {
            return Ok(state);
        }

        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        conn.execute(
            "INSERT INTO agent_coding_session_state (session_id, agent_status, updated_at)
             VALUES (?1, 'idle', ?2)",
            params![session_id.as_str(), now],
        )?;
        drop(conn);

        self.get_session_state(session_id)?
            .ok_or_else(|| rusqlite::Error::QueryReturnedNoRows)
    }

    /// Gets session state.
    pub fn get_session_state(&self, session_id: &SessionId) -> SqliteResult<Option<SessionState>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT session_id, agent_status, queued_commands, diff_summary, updated_at
             FROM agent_coding_session_state WHERE session_id = ?1",
        )?;

        let result = stmt.query_row(params![session_id.as_str()], |row| {
            Ok(SessionState {
                session_id: SessionId::from_string(row.get::<_, String>(0)?),
                agent_status: AgentStatus::from_str(&row.get::<_, String>(1)?),
                queued_commands: row.get(2)?,
                diff_summary: row.get(3)?,
                updated_at: Self::parse_datetime(row.get::<_, String>(4)?),
            })
        });

        match result {
            Ok(state) => Ok(Some(state)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Updates agent status.
    pub fn update_agent_status(&self, session_id: &SessionId, status: AgentStatus) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        let count = conn.execute(
            "UPDATE agent_coding_session_state SET agent_status = ?1, updated_at = ?2 WHERE session_id = ?3",
            params![status.as_str(), now, session_id.as_str()],
        )?;
        Ok(count > 0)
    }

    // ========================================================================
    // Agent message operations (new table)
    // ========================================================================

    /// Inserts a message into the agent messages table with atomic sequence assignment.
    pub fn insert_agent_message(&self, session: &SessionId, msg: &NewMessage) -> SqliteResult<InsertedMessage> {
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

        Ok(InsertedMessage { id, sequence_number })
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
    pub fn get_session_secret(&self, session_id: &SessionId) -> SqliteResult<Option<SessionSecret>> {
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
            params![secret.session_id.as_str(), secret.encrypted_secret, secret.nonce, now],
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
    // Outbox operations
    // ========================================================================

    /// Inserts a new outbox event.
    pub fn insert_outbox_event(&self, event: &NewOutboxEvent) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        conn.execute(
            "INSERT INTO agent_coding_session_event_outbox (event_id, session_id, sequence_number, message_id, status, created_at)
             VALUES (?1, ?2, ?3, ?4, 'pending', ?5)",
            params![
                event.event_id,
                event.session_id.as_str(),
                event.sequence_number,
                event.message_id.as_str(),
                now,
            ],
        )?;
        Ok(())
    }

    /// Gets pending outbox events for a session (limited to batch size).
    pub fn get_pending_outbox_events(&self, session_id: &SessionId, limit: usize) -> SqliteResult<Vec<OutboxEvent>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT event_id, session_id, sequence_number, relay_send_batch_id, message_id, status, retry_count, last_error, created_at, sent_at, acked_at
             FROM agent_coding_session_event_outbox
             WHERE session_id = ?1 AND status = 'pending'
             ORDER BY sequence_number ASC
             LIMIT ?2",
        )?;

        let events = stmt
            .query_map(params![session_id.as_str(), limit as i64], |row| {
                Ok(OutboxEvent {
                    event_id: row.get(0)?,
                    session_id: SessionId::from_string(row.get::<_, String>(1)?),
                    sequence_number: row.get(2)?,
                    relay_send_batch_id: row.get(3)?,
                    message_id: MessageId::from_string(row.get::<_, String>(4)?),
                    status: OutboxStatus::from_str(&row.get::<_, String>(5)?),
                    retry_count: row.get(6)?,
                    last_error: row.get(7)?,
                    created_at: Self::parse_datetime(row.get::<_, String>(8)?),
                    sent_at: row.get::<_, Option<String>>(9)?.map(Self::parse_datetime),
                    acked_at: row.get::<_, Option<String>>(10)?.map(Self::parse_datetime),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(events)
    }

    /// Marks outbox events as sent with a batch ID.
    pub fn mark_outbox_events_sent(&self, event_ids: &[String], batch_id: &str) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        for event_id in event_ids {
            conn.execute(
                "UPDATE agent_coding_session_event_outbox
                 SET status = 'sent', relay_send_batch_id = ?1, sent_at = ?2
                 WHERE event_id = ?3",
                params![batch_id, now, event_id],
            )?;
        }
        Ok(())
    }

    /// Marks outbox events as acknowledged by batch ID.
    pub fn mark_outbox_batch_acked(&self, batch_id: &str) -> SqliteResult<usize> {
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        let count = conn.execute(
            "UPDATE agent_coding_session_event_outbox
             SET status = 'acked', acked_at = ?1
             WHERE relay_send_batch_id = ?2",
            params![now, batch_id],
        )?;
        Ok(count)
    }

    /// Resets sent events to pending (for crash recovery).
    #[allow(dead_code)]
    pub fn reset_sent_events_to_pending(&self, session_id: &SessionId) -> SqliteResult<usize> {
        let conn = self.conn.lock().expect("lock poisoned");
        let count = conn.execute(
            "UPDATE agent_coding_session_event_outbox
             SET status = 'pending', relay_send_batch_id = NULL, sent_at = NULL
             WHERE session_id = ?1 AND status = 'sent'",
            params![session_id.as_str()],
        )?;
        Ok(count)
    }

    /// Gets the next outbox sequence number for a session.
    #[allow(dead_code)]
    pub fn get_next_outbox_sequence(&self, session_id: &SessionId) -> SqliteResult<i64> {
        let conn = self.conn.lock().expect("lock poisoned");
        let max: Option<i64> = conn.query_row(
            "SELECT MAX(sequence_number) FROM agent_coding_session_event_outbox WHERE session_id = ?1",
            params![session_id.as_str()],
            |row| row.get(0),
        )?;
        Ok(max.unwrap_or(0) + 1)
    }

    // ========================================================================
    // Supabase message outbox operations
    // ========================================================================

    /// Insert a message into the Supabase message outbox.
    pub fn insert_supabase_message_outbox(&self, message_id: &MessageId) -> SqliteResult<()> {
        let conn = self.conn.lock().expect("lock poisoned");
        conn.execute(
            "INSERT OR IGNORE INTO agent_coding_session_message_supabase_outbox (message_id)
             VALUES (?1)",
            params![message_id.as_str()],
        )?;
        Ok(())
    }

    /// Get pending Supabase messages (joined with message content).
    pub fn get_pending_supabase_messages(&self, limit: usize) -> SqliteResult<Vec<crate::types::PendingSupabaseMessage>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare_cached(
            "SELECT o.message_id, m.session_id, m.sequence_number, m.content,
                    o.created_at, o.last_attempt_at, o.retry_count, o.last_error
             FROM agent_coding_session_message_supabase_outbox o
             JOIN agent_coding_session_messages m ON m.id = o.message_id
             WHERE o.sent_at IS NULL
             ORDER BY o.created_at ASC
             LIMIT ?1",
        )?;

        let rows = stmt
            .query_map(params![limit as i64], |row| {
                Ok(crate::types::PendingSupabaseMessage {
                    message_id: MessageId::from_string(row.get::<_, String>(0)?),
                    session_id: SessionId::from_string(row.get::<_, String>(1)?),
                    sequence_number: row.get(2)?,
                    content: row.get(3)?,
                    created_at: Self::parse_datetime(row.get::<_, String>(4)?),
                    last_attempt_at: row.get::<_, Option<String>>(5)?.map(Self::parse_datetime),
                    retry_count: row.get(6)?,
                    last_error: row.get(7)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(rows)
    }

    /// Mark messages as successfully sent to Supabase.
    pub fn mark_supabase_messages_sent(&self, message_ids: &[MessageId]) -> SqliteResult<()> {
        if message_ids.is_empty() {
            return Ok(());
        }
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        let placeholders = std::iter::repeat("?").take(message_ids.len()).collect::<Vec<_>>().join(", ");
        let sql = format!(
            "UPDATE agent_coding_session_message_supabase_outbox
             SET sent_at = ?1, last_error = NULL
             WHERE message_id IN ({})",
            placeholders
        );

        let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(message_ids.len() + 1);
        params_vec.push(&now);
        for id in message_ids {
            params_vec.push(&id.0);
        }

        conn.execute(&sql, params_vec.as_slice())?;
        Ok(())
    }

    /// Mark messages as failed to sync (increments retry count).
    pub fn mark_supabase_messages_failed(&self, message_ids: &[MessageId], error: &str) -> SqliteResult<()> {
        if message_ids.is_empty() {
            return Ok(());
        }
        let conn = self.conn.lock().expect("lock poisoned");
        let now = Self::now_rfc3339();
        let placeholders = std::iter::repeat("?").take(message_ids.len()).collect::<Vec<_>>().join(", ");
        let sql = format!(
            "UPDATE agent_coding_session_message_supabase_outbox
             SET last_attempt_at = ?1,
                 retry_count = retry_count + 1,
                 last_error = ?2
             WHERE message_id IN ({})",
            placeholders
        );

        let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(message_ids.len() + 2);
        params_vec.push(&now);
        params_vec.push(&error);
        for id in message_ids {
            params_vec.push(&id.0);
        }

        conn.execute(&sql, params_vec.as_slice())?;
        Ok(())
    }

    /// Delete messages from the Supabase outbox.
    pub fn delete_supabase_message_outbox(&self, message_ids: &[MessageId]) -> SqliteResult<()> {
        if message_ids.is_empty() {
            return Ok(());
        }
        let conn = self.conn.lock().expect("lock poisoned");
        let placeholders = std::iter::repeat("?").take(message_ids.len()).collect::<Vec<_>>().join(", ");
        let sql = format!(
            "DELETE FROM agent_coding_session_message_supabase_outbox
             WHERE message_id IN ({})",
            placeholders
        );

        let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(message_ids.len());
        for id in message_ids {
            params_vec.push(&id.0);
        }

        conn.execute(&sql, params_vec.as_slice())?;
        Ok(())
    }

    // ========================================================================
    // User settings operations
    // ========================================================================

    /// Gets a user setting.
    #[allow(dead_code)]
    pub fn get_setting(&self, key: &str) -> SqliteResult<Option<UserSetting>> {
        let conn = self.conn.lock().expect("lock poisoned");
        let mut stmt = conn.prepare("SELECT key, value, value_type, updated_at FROM user_settings WHERE key = ?1")?;

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
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        };
        store.insert_agent_session(&session).unwrap();

        let retrieved = store.get_agent_session(&id).unwrap().unwrap();
        assert_eq!(retrieved.id.as_str(), "my-custom-session-id");
    }

    #[test]
    fn supabase_message_outbox_crud() {
        let store = SqliteStore::in_memory().unwrap();
        let repo_id = create_test_repo(&store);
        let session_id = create_test_session(&store, &repo_id);

        let inserted = store
            .insert_agent_message(&session_id, &NewMessage { content: "Hello".to_string() })
            .unwrap();

        store
            .insert_supabase_message_outbox(&inserted.id)
            .unwrap();

        let pending = store.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].message_id, inserted.id);
        assert_eq!(pending[0].sequence_number, inserted.sequence_number);

        store
            .mark_supabase_messages_failed(&[inserted.id.clone()], "test error")
            .unwrap();

        let pending = store.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending[0].retry_count, 1);
        assert_eq!(pending[0].last_error.as_deref(), Some("test error"));

        store
            .mark_supabase_messages_sent(&[inserted.id.clone()])
            .unwrap();

        store
            .delete_supabase_message_outbox(&[inserted.id.clone()])
            .unwrap();

        let pending = store.get_pending_supabase_messages(10).unwrap();
        assert!(pending.is_empty());
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
            .insert_agent_message(&session_id, &NewMessage { content: "First".to_string() })
            .unwrap();
        assert_eq!(inserted1.sequence_number, 1);

        // Second message should get sequence 2
        let inserted2 = store
            .insert_agent_message(&session_id, &NewMessage { content: "Second".to_string() })
            .unwrap();
        assert_eq!(inserted2.sequence_number, 2);

        // Third message should get sequence 3
        let inserted3 = store
            .insert_agent_message(&session_id, &NewMessage { content: "Third".to_string() })
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
            .insert_agent_message(&session1, &NewMessage { content: "S1-M1".to_string() })
            .unwrap();
        let msg2 = store
            .insert_agent_message(&session2, &NewMessage { content: "S2-M1".to_string() })
            .unwrap();
        let msg3 = store
            .insert_agent_message(&session1, &NewMessage { content: "S1-M2".to_string() })
            .unwrap();

        assert_eq!(msg1.sequence_number, 1); // session1 starts at 1
        assert_eq!(msg2.sequence_number, 1); // session2 starts at 1
        assert_eq!(msg3.sequence_number, 2); // session1 continues to 2
    }
}
