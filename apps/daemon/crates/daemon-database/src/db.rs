//! Database connection and query operations.

use crate::{
    migrations, AgentCodingSession, AgentCodingSessionMessage, AgentCodingSessionState,
    AgentStatus, DatabaseError, DatabaseResult, NewAgentCodingSession,
    NewAgentCodingSessionMessage, NewRepository, NewSessionSecret, Repository, SessionSecret,
    SessionStatus, SupabaseMessageOutboxPending, UserSetting,
};
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use std::path::Path;
use tracing::debug;

/// Database wrapper with query methods.
pub struct Database {
    conn: Connection,
}

impl Database {
    /// Open a database at the given path, running migrations if needed.
    pub fn open(path: &Path) -> DatabaseResult<Self> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let conn = Connection::open(path)?;

        // Enable WAL mode and performance optimizations
        conn.execute_batch(
            "
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA cache_size = -64000;
            PRAGMA temp_store = MEMORY;
            PRAGMA mmap_size = 268435456;
            PRAGMA busy_timeout = 5000;
        ",
        )?;

        // Run migrations
        migrations::run_migrations(&conn)?;

        Ok(Self { conn })
    }

    /// Open an in-memory database for testing.
    pub fn open_in_memory() -> DatabaseResult<Self> {
        let conn = Connection::open_in_memory()?;
        // Note: WAL mode doesn't apply to in-memory databases
        conn.execute_batch(
            "
            PRAGMA foreign_keys = ON;
            PRAGMA cache_size = -64000;
            PRAGMA temp_store = MEMORY;
        ",
        )?;
        migrations::run_migrations(&conn)?;
        Ok(Self { conn })
    }

    /// Get a reference to the underlying connection.
    pub fn connection(&self) -> &Connection {
        &self.conn
    }

    // ==========================================
    // Repositories
    // ==========================================

    /// Insert a new repository.
    pub fn insert_repository(&self, repo: &NewRepository) -> DatabaseResult<Repository> {
        let now = Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO repositories (id, path, name, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?4, ?5, ?6, ?7, ?8, ?4, ?4)",
            params![
                repo.id,
                repo.path,
                repo.name,
                now,
                repo.is_git_repository,
                repo.sessions_path,
                repo.default_branch,
                repo.default_remote,
            ],
        )?;
        self.get_repository(&repo.id)?
            .ok_or_else(|| DatabaseError::NotFound("Repository not found after insert".to_string()))
    }

    /// Get a repository by ID.
    pub fn get_repository(&self, id: &str) -> DatabaseResult<Option<Repository>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, path, name, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
             FROM repositories WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id], |row| {
            Ok(Repository {
                id: row.get(0)?,
                path: row.get(1)?,
                name: row.get(2)?,
                last_accessed_at: parse_datetime(row.get::<_, String>(3)?),
                added_at: parse_datetime(row.get::<_, String>(4)?),
                is_git_repository: row.get(5)?,
                sessions_path: row.get(6)?,
                default_branch: row.get(7)?,
                default_remote: row.get(8)?,
                created_at: parse_datetime(row.get::<_, String>(9)?),
                updated_at: parse_datetime(row.get::<_, String>(10)?),
            })
        });

        match result {
            Ok(repo) => Ok(Some(repo)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// Get a repository by path.
    pub fn get_repository_by_path(&self, path: &str) -> DatabaseResult<Option<Repository>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, path, name, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
             FROM repositories WHERE path = ?1",
        )?;

        let result = stmt.query_row(params![path], |row| {
            Ok(Repository {
                id: row.get(0)?,
                path: row.get(1)?,
                name: row.get(2)?,
                last_accessed_at: parse_datetime(row.get::<_, String>(3)?),
                added_at: parse_datetime(row.get::<_, String>(4)?),
                is_git_repository: row.get(5)?,
                sessions_path: row.get(6)?,
                default_branch: row.get(7)?,
                default_remote: row.get(8)?,
                created_at: parse_datetime(row.get::<_, String>(9)?),
                updated_at: parse_datetime(row.get::<_, String>(10)?),
            })
        });

        match result {
            Ok(repo) => Ok(Some(repo)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// List all repositories ordered by last accessed.
    pub fn list_repositories(&self) -> DatabaseResult<Vec<Repository>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, path, name, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
             FROM repositories ORDER BY last_accessed_at DESC",
        )?;

        let repos = stmt
            .query_map([], |row| {
                Ok(Repository {
                    id: row.get(0)?,
                    path: row.get(1)?,
                    name: row.get(2)?,
                    last_accessed_at: parse_datetime(row.get::<_, String>(3)?),
                    added_at: parse_datetime(row.get::<_, String>(4)?),
                    is_git_repository: row.get(5)?,
                    sessions_path: row.get(6)?,
                    default_branch: row.get(7)?,
                    default_remote: row.get(8)?,
                    created_at: parse_datetime(row.get::<_, String>(9)?),
                    updated_at: parse_datetime(row.get::<_, String>(10)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(repos)
    }

    /// Delete a repository by ID.
    pub fn delete_repository(&self, id: &str) -> DatabaseResult<bool> {
        let count = self
            .conn
            .execute("DELETE FROM repositories WHERE id = ?1", params![id])?;
        Ok(count > 0)
    }

    // ==========================================
    // Sessions
    // ==========================================

    /// Insert a new session.
    pub fn insert_session(
        &self,
        session: &NewAgentCodingSession,
    ) -> DatabaseResult<AgentCodingSession> {
        let now = Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO agent_coding_sessions (id, repository_id, title, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, 'active', ?5, ?6, ?7, ?7, ?7)",
            params![
                session.id,
                session.repository_id,
                session.title,
                session.claude_session_id,
                session.is_worktree,
                session.worktree_path,
                now,
            ],
        )?;
        self.get_session(&session.id)?
            .ok_or_else(|| DatabaseError::NotFound("Session not found after insert".to_string()))
    }

    /// Get a session by ID.
    pub fn get_session(&self, id: &str) -> DatabaseResult<Option<AgentCodingSession>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, repository_id, title, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
             FROM agent_coding_sessions WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id], |row| {
            Ok(AgentCodingSession {
                id: row.get(0)?,
                repository_id: row.get(1)?,
                title: row.get(2)?,
                claude_session_id: row.get(3)?,
                status: SessionStatus::from_str(&row.get::<_, String>(4)?),
                is_worktree: row.get(5)?,
                worktree_path: row.get(6)?,
                created_at: parse_datetime(row.get::<_, String>(7)?),
                last_accessed_at: parse_datetime(row.get::<_, String>(8)?),
                updated_at: parse_datetime(row.get::<_, String>(9)?),
            })
        });

        match result {
            Ok(session) => Ok(Some(session)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// List sessions for a repository.
    pub fn list_sessions_for_repository(
        &self,
        repository_id: &str,
    ) -> DatabaseResult<Vec<AgentCodingSession>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, repository_id, title, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
             FROM agent_coding_sessions WHERE repository_id = ?1 ORDER BY last_accessed_at DESC",
        )?;

        let sessions = stmt
            .query_map(params![repository_id], |row| {
                Ok(AgentCodingSession {
                    id: row.get(0)?,
                    repository_id: row.get(1)?,
                    title: row.get(2)?,
                    claude_session_id: row.get(3)?,
                    status: SessionStatus::from_str(&row.get::<_, String>(4)?),
                    is_worktree: row.get(5)?,
                    worktree_path: row.get(6)?,
                    created_at: parse_datetime(row.get::<_, String>(7)?),
                    last_accessed_at: parse_datetime(row.get::<_, String>(8)?),
                    updated_at: parse_datetime(row.get::<_, String>(9)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(sessions)
    }

    /// Update session title.
    pub fn update_session_title(&self, id: &str, title: &str) -> DatabaseResult<bool> {
        let now = Utc::now().to_rfc3339();
        let count = self.conn.execute(
            "UPDATE agent_coding_sessions SET title = ?1, updated_at = ?2 WHERE id = ?3",
            params![title, now, id],
        )?;
        Ok(count > 0)
    }

    /// Update session last accessed time.
    pub fn touch_session(&self, id: &str) -> DatabaseResult<bool> {
        let now = Utc::now().to_rfc3339();
        let count = self.conn.execute(
            "UPDATE agent_coding_sessions SET last_accessed_at = ?1, updated_at = ?1 WHERE id = ?2",
            params![now, id],
        )?;
        Ok(count > 0)
    }

    /// Delete a session by ID.
    pub fn delete_session(&self, id: &str) -> DatabaseResult<bool> {
        let count = self.conn.execute(
            "DELETE FROM agent_coding_sessions WHERE id = ?1",
            params![id],
        )?;
        Ok(count > 0)
    }

    /// Update the Claude session ID for a session.
    pub fn update_session_claude_id(
        &self,
        id: &str,
        claude_session_id: &str,
    ) -> DatabaseResult<bool> {
        let now = Utc::now().to_rfc3339();
        let count = self.conn.execute(
            "UPDATE agent_coding_sessions SET claude_session_id = ?1, updated_at = ?2 WHERE id = ?3",
            params![claude_session_id, now, id],
        )?;
        Ok(count > 0)
    }

    // ==========================================
    // Session State
    // ==========================================

    /// Get or create session state.
    pub fn get_or_create_session_state(
        &self,
        session_id: &str,
    ) -> DatabaseResult<AgentCodingSessionState> {
        if let Some(state) = self.get_session_state(session_id)? {
            return Ok(state);
        }

        let now_ms = now_timestamp_ms();
        self.conn.execute(
            "INSERT INTO agent_coding_session_state (session_id, state_json, updated_at_ms)
             VALUES (
                ?1,
                json_object(
                    'schema_version', 1,
                    'coding_session', json_object('status', 'idle'),
                    'device_id', ?2,
                    'session_id', ?1,
                    'updated_at_ms', ?3
                ),
                ?3
             )",
            params![session_id, DEFAULT_RUNTIME_DEVICE_ID, now_ms],
        )?;

        self.get_session_state(session_id)?.ok_or_else(|| {
            DatabaseError::NotFound("Session state not found after insert".to_string())
        })
    }

    /// Get session state.
    pub fn get_session_state(
        &self,
        session_id: &str,
    ) -> DatabaseResult<Option<AgentCodingSessionState>> {
        let mut stmt = self.conn.prepare(
            "SELECT
                session_id,
                json_extract(state_json, '$.coding_session.status') AS agent_status,
                updated_at_ms
             FROM agent_coding_session_state WHERE session_id = ?1",
        )?;

        let result = stmt.query_row(params![session_id], |row| {
            let raw_status: Option<String> = row.get(1)?;
            let updated_at_ms: i64 = row.get(2)?;
            Ok(AgentCodingSessionState {
                session_id: row.get(0)?,
                agent_status: AgentStatus::from_str(raw_status.as_deref().unwrap_or("idle")),
                queued_commands: None,
                diff_summary: None,
                updated_at: parse_datetime_from_millis(updated_at_ms),
            })
        });

        match result {
            Ok(state) => Ok(Some(state)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// Update agent status.
    pub fn update_agent_status(
        &self,
        session_id: &str,
        status: AgentStatus,
    ) -> DatabaseResult<bool> {
        let now_ms = now_timestamp_ms();
        let count = self.conn.execute(
            "UPDATE agent_coding_session_state
             SET
                state_json = json_remove(
                    json_set(
                        COALESCE(
                            state_json,
                            json_object(
                                'schema_version', 1,
                                'coding_session', json_object('status', 'idle'),
                                'device_id', ?1,
                                'session_id', ?3,
                                'updated_at_ms', ?2
                            )
                        ),
                        '$.schema_version', 1,
                        '$.coding_session.status', ?4,
                        '$.session_id', ?3,
                        '$.updated_at_ms', ?2
                    ),
                    '$.coding_session.error_message'
                ),
                updated_at_ms = ?2
             WHERE session_id = ?3",
            params![
                DEFAULT_RUNTIME_DEVICE_ID,
                now_ms,
                session_id,
                status.as_str()
            ],
        )?;
        Ok(count > 0)
    }

    // ==========================================
    // Messages
    // ==========================================

    /// Insert a new message.
    pub fn insert_message(&self, message: &NewAgentCodingSessionMessage) -> DatabaseResult<()> {
        let now = Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO agent_coding_session_messages (id, session_id, content, timestamp, is_streaming, sequence_number, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?4)",
            params![
                message.id,
                message.session_id,
                message.content,
                now,
                message.is_streaming,
                message.sequence_number,
            ],
        )?;
        Ok(())
    }

    /// Get a message by ID.
    pub fn get_message(&self, id: &str) -> DatabaseResult<Option<AgentCodingSessionMessage>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, session_id, content, timestamp, is_streaming, sequence_number, created_at
             FROM agent_coding_session_messages WHERE id = ?1",
        )?;

        let result = stmt.query_row(params![id], |row| {
            Ok(AgentCodingSessionMessage {
                id: row.get(0)?,
                session_id: row.get(1)?,
                content: row.get(2)?,
                timestamp: parse_datetime(row.get::<_, String>(3)?),
                is_streaming: row.get(4)?,
                sequence_number: row.get(5)?,
                created_at: parse_datetime(row.get::<_, String>(6)?),
            })
        });

        match result {
            Ok(msg) => Ok(Some(msg)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// List messages for a session ordered by sequence number.
    pub fn list_messages_for_session(
        &self,
        session_id: &str,
    ) -> DatabaseResult<Vec<AgentCodingSessionMessage>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, session_id, content, timestamp, is_streaming, sequence_number, created_at
             FROM agent_coding_session_messages WHERE session_id = ?1 ORDER BY sequence_number ASC",
        )?;

        let messages = stmt
            .query_map(params![session_id], |row| {
                Ok(AgentCodingSessionMessage {
                    id: row.get(0)?,
                    session_id: row.get(1)?,
                    content: row.get(2)?,
                    timestamp: parse_datetime(row.get::<_, String>(3)?),
                    is_streaming: row.get(4)?,
                    sequence_number: row.get(5)?,
                    created_at: parse_datetime(row.get::<_, String>(6)?),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(messages)
    }

    /// Get the next sequence number for a session.
    pub fn get_next_message_sequence(&self, session_id: &str) -> DatabaseResult<i64> {
        let max: Option<i64> = self.conn.query_row(
            "SELECT MAX(sequence_number) FROM agent_coding_session_messages WHERE session_id = ?1",
            params![session_id],
            |row| row.get(0),
        )?;
        Ok(max.unwrap_or(0) + 1)
    }

    // ==========================================
    // Supabase Message Outbox
    // ==========================================

    /// Insert a message into the Supabase outbox.
    pub fn insert_supabase_message_outbox(&self, message_id: &str) -> DatabaseResult<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO agent_coding_session_message_supabase_outbox (message_id)
             VALUES (?1)",
            params![message_id],
        )?;
        Ok(())
    }

    /// Get pending Supabase message outbox entries (joined with message content).
    pub fn get_pending_supabase_messages(
        &self,
        limit: usize,
    ) -> DatabaseResult<Vec<SupabaseMessageOutboxPending>> {
        let mut stmt = self.conn.prepare(
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
                Ok(SupabaseMessageOutboxPending {
                    message_id: row.get(0)?,
                    session_id: row.get(1)?,
                    sequence_number: row.get(2)?,
                    content: row.get(3)?,
                    created_at: parse_datetime(row.get::<_, String>(4)?),
                    last_attempt_at: row.get::<_, Option<String>>(5)?.map(parse_datetime),
                    retry_count: row.get(6)?,
                    last_error: row.get(7)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(rows)
    }

    /// Mark messages as sent to Supabase.
    pub fn mark_supabase_messages_sent(&self, message_ids: &[String]) -> DatabaseResult<()> {
        if message_ids.is_empty() {
            return Ok(());
        }
        let now = Utc::now().to_rfc3339();
        let placeholders = std::iter::repeat("?")
            .take(message_ids.len())
            .collect::<Vec<_>>()
            .join(", ");
        let sql = format!(
            "UPDATE agent_coding_session_message_supabase_outbox
             SET sent_at = ?1, last_error = NULL
             WHERE message_id IN ({})",
            placeholders
        );

        let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(message_ids.len() + 1);
        params_vec.push(&now);
        for id in message_ids {
            params_vec.push(id);
        }

        self.conn.execute(&sql, params_vec.as_slice())?;
        Ok(())
    }

    /// Mark messages as failed to sync (increments retry count).
    pub fn mark_supabase_messages_failed(
        &self,
        message_ids: &[String],
        error: &str,
    ) -> DatabaseResult<()> {
        if message_ids.is_empty() {
            return Ok(());
        }
        let now = Utc::now().to_rfc3339();
        let placeholders = std::iter::repeat("?")
            .take(message_ids.len())
            .collect::<Vec<_>>()
            .join(", ");
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
            params_vec.push(id);
        }

        self.conn.execute(&sql, params_vec.as_slice())?;
        Ok(())
    }

    /// Delete messages from the Supabase outbox.
    pub fn delete_supabase_message_outbox(&self, message_ids: &[String]) -> DatabaseResult<()> {
        if message_ids.is_empty() {
            return Ok(());
        }
        let placeholders = std::iter::repeat("?")
            .take(message_ids.len())
            .collect::<Vec<_>>()
            .join(", ");
        let sql = format!(
            "DELETE FROM agent_coding_session_message_supabase_outbox
             WHERE message_id IN ({})",
            placeholders
        );

        let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(message_ids.len());
        for id in message_ids {
            params_vec.push(id);
        }

        self.conn.execute(&sql, params_vec.as_slice())?;
        Ok(())
    }

    // ==========================================
    // User Settings
    // ==========================================

    /// Get a user setting.
    pub fn get_setting(&self, key: &str) -> DatabaseResult<Option<UserSetting>> {
        let mut stmt = self.conn.prepare(
            "SELECT key, value, value_type, updated_at FROM user_settings WHERE key = ?1",
        )?;

        let result = stmt.query_row(params![key], |row| {
            Ok(UserSetting {
                key: row.get(0)?,
                value: row.get(1)?,
                value_type: row.get(2)?,
                updated_at: parse_datetime(row.get::<_, String>(3)?),
            })
        });

        match result {
            Ok(setting) => Ok(Some(setting)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// Set a user setting.
    pub fn set_setting(&self, key: &str, value: &str, value_type: &str) -> DatabaseResult<()> {
        let now = Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO user_settings (key, value, value_type, updated_at)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(key) DO UPDATE SET value = ?2, value_type = ?3, updated_at = ?4",
            params![key, value, value_type, now],
        )?;
        Ok(())
    }

    /// Delete a user setting.
    pub fn delete_setting(&self, key: &str) -> DatabaseResult<bool> {
        let count = self
            .conn
            .execute("DELETE FROM user_settings WHERE key = ?1", params![key])?;
        Ok(count > 0)
    }

    // ==========================================
    // Session Secrets
    // ==========================================

    /// Get a session secret by session ID.
    /// Returns the encrypted secret and nonce (encrypted with device key).
    pub fn get_session_secret(&self, session_id: &str) -> DatabaseResult<Option<SessionSecret>> {
        let mut stmt = self.conn.prepare(
            "SELECT session_id, encrypted_secret, nonce, created_at
             FROM session_secrets WHERE session_id = ?1",
        )?;

        let result = stmt.query_row(params![session_id], |row| {
            Ok(SessionSecret {
                session_id: row.get(0)?,
                encrypted_secret: row.get(1)?,
                nonce: row.get(2)?,
                created_at: parse_datetime(row.get::<_, String>(3)?),
            })
        });

        match result {
            Ok(secret) => Ok(Some(secret)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    /// Store a session secret (upsert).
    pub fn set_session_secret(&self, secret: &NewSessionSecret) -> DatabaseResult<()> {
        let now = Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO session_secrets (session_id, encrypted_secret, nonce, created_at)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(session_id) DO UPDATE SET encrypted_secret = ?2, nonce = ?3",
            params![
                secret.session_id,
                secret.encrypted_secret,
                secret.nonce,
                now,
            ],
        )?;
        debug!(session_id = %secret.session_id, "Session secret stored");
        Ok(())
    }

    /// Delete a session secret.
    pub fn delete_session_secret(&self, session_id: &str) -> DatabaseResult<bool> {
        let count = self.conn.execute(
            "DELETE FROM session_secrets WHERE session_id = ?1",
            params![session_id],
        )?;
        Ok(count > 0)
    }

    /// Check if a session secret exists.
    pub fn has_session_secret(&self, session_id: &str) -> DatabaseResult<bool> {
        let count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM session_secrets WHERE session_id = ?1",
            params![session_id],
            |row| row.get(0),
        )?;
        Ok(count > 0)
    }
}

/// Parse an RFC3339 datetime string, falling back to current time on error.
fn parse_datetime(s: String) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(&s)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now())
}

const DEFAULT_RUNTIME_DEVICE_ID: &str = "00000000-0000-0000-0000-000000000000";

fn now_timestamp_ms() -> i64 {
    Utc::now().timestamp_millis()
}

fn parse_datetime_from_millis(ms: i64) -> DateTime<Utc> {
    DateTime::<Utc>::from_timestamp_millis(ms).unwrap_or_else(Utc::now)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_db() -> Database {
        Database::open_in_memory().unwrap()
    }

    fn setup_test_repo_and_session(db: &Database) -> (String, String) {
        let repo_id = "repo-1".to_string();
        let session_id = "session-1".to_string();

        db.insert_repository(&NewRepository {
            id: repo_id.clone(),
            path: "/path/to/repo".to_string(),
            name: "my-repo".to_string(),
            is_git_repository: true,
            sessions_path: None,
            default_branch: None,
            default_remote: None,
        })
        .unwrap();

        db.insert_session(&NewAgentCodingSession {
            id: session_id.clone(),
            repository_id: repo_id.clone(),
            title: "Test Session".to_string(),
            claude_session_id: None,
            is_worktree: false,
            worktree_path: None,
        })
        .unwrap();

        (repo_id, session_id)
    }

    #[test]
    fn test_repository_crud() {
        let db = create_test_db();

        // Insert
        let repo = db
            .insert_repository(&NewRepository {
                id: "repo-1".to_string(),
                path: "/path/to/repo".to_string(),
                name: "my-repo".to_string(),
                is_git_repository: true,
                sessions_path: None,
                default_branch: Some("main".to_string()),
                default_remote: Some("origin".to_string()),
            })
            .unwrap();

        assert_eq!(repo.id, "repo-1");
        assert_eq!(repo.name, "my-repo");
        assert!(repo.is_git_repository);

        // Get by ID
        let fetched = db.get_repository("repo-1").unwrap().unwrap();
        assert_eq!(fetched.path, "/path/to/repo");

        // Get by path
        let fetched = db.get_repository_by_path("/path/to/repo").unwrap().unwrap();
        assert_eq!(fetched.id, "repo-1");

        // List
        let repos = db.list_repositories().unwrap();
        assert_eq!(repos.len(), 1);

        // Delete
        assert!(db.delete_repository("repo-1").unwrap());
        assert!(db.get_repository("repo-1").unwrap().is_none());
    }

    #[test]
    fn test_session_crud() {
        let db = create_test_db();

        // Create repository first
        db.insert_repository(&NewRepository {
            id: "repo-1".to_string(),
            path: "/path/to/repo".to_string(),
            name: "my-repo".to_string(),
            is_git_repository: true,
            sessions_path: None,
            default_branch: None,
            default_remote: None,
        })
        .unwrap();

        // Insert session
        let session = db
            .insert_session(&NewAgentCodingSession {
                id: "session-1".to_string(),
                repository_id: "repo-1".to_string(),
                title: "Test Session".to_string(),
                claude_session_id: Some("claude-123".to_string()),
                is_worktree: false,
                worktree_path: None,
            })
            .unwrap();

        assert_eq!(session.id, "session-1");
        assert_eq!(session.title, "Test Session");

        // Update title
        assert!(db
            .update_session_title("session-1", "Updated Title")
            .unwrap());
        let fetched = db.get_session("session-1").unwrap().unwrap();
        assert_eq!(fetched.title, "Updated Title");

        // List sessions
        let sessions = db.list_sessions_for_repository("repo-1").unwrap();
        assert_eq!(sessions.len(), 1);

        // Delete
        assert!(db.delete_session("session-1").unwrap());
        assert!(db.get_session("session-1").unwrap().is_none());
    }

    #[test]
    fn test_user_settings() {
        let db = create_test_db();

        // Set
        db.set_setting("theme", "dark", "string").unwrap();

        // Get
        let setting = db.get_setting("theme").unwrap().unwrap();
        assert_eq!(setting.value, "dark");
        assert_eq!(setting.value_type, "string");

        // Update
        db.set_setting("theme", "light", "string").unwrap();
        let setting = db.get_setting("theme").unwrap().unwrap();
        assert_eq!(setting.value, "light");

        // Delete
        assert!(db.delete_setting("theme").unwrap());
        assert!(db.get_setting("theme").unwrap().is_none());
    }

    #[test]
    fn test_session_state_lifecycle() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        // Get or create creates new state
        let state = db.get_or_create_session_state(&session_id).unwrap();
        assert_eq!(state.session_id, session_id);
        assert_eq!(state.agent_status, AgentStatus::Idle);
        assert!(state.queued_commands.is_none());
        assert!(state.diff_summary.is_none());

        // Update agent status
        assert!(db
            .update_agent_status(&session_id, AgentStatus::Running)
            .unwrap());
        let state = db.get_session_state(&session_id).unwrap().unwrap();
        assert_eq!(state.agent_status, AgentStatus::Running);

        // Update to waiting
        assert!(db
            .update_agent_status(&session_id, AgentStatus::Waiting)
            .unwrap());
        let state = db.get_session_state(&session_id).unwrap().unwrap();
        assert_eq!(state.agent_status, AgentStatus::Waiting);

        // Get or create returns existing state
        let state = db.get_or_create_session_state(&session_id).unwrap();
        assert_eq!(state.agent_status, AgentStatus::Waiting);
    }

    #[test]
    fn test_message_crud() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        // Insert message with plain text content
        let msg = NewAgentCodingSessionMessage {
            id: "msg-1".to_string(),
            session_id: session_id.clone(),
            content: r#"{"type":"user","content":"hello"}"#.to_string(),
            sequence_number: 1,
            is_streaming: false,
        };
        db.insert_message(&msg).unwrap();

        // Get message
        let fetched = db.get_message("msg-1").unwrap().unwrap();
        assert_eq!(fetched.id, "msg-1");
        assert_eq!(fetched.session_id, session_id);
        assert_eq!(fetched.content, r#"{"type":"user","content":"hello"}"#);
        assert_eq!(fetched.sequence_number, 1);
        assert!(!fetched.is_streaming);

        // List messages
        let messages = db.list_messages_for_session(&session_id).unwrap();
        assert_eq!(messages.len(), 1);

        // Non-existent message returns None
        assert!(db.get_message("nonexistent").unwrap().is_none());
    }

    #[test]
    fn test_message_sequence_numbers() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        // First sequence should be 1
        let seq1 = db.get_next_message_sequence(&session_id).unwrap();
        assert_eq!(seq1, 1);

        // Insert message with sequence 1
        db.insert_message(&NewAgentCodingSessionMessage {
            id: "msg-1".to_string(),
            session_id: session_id.clone(),
            content: "message 1".to_string(),
            sequence_number: seq1,
            is_streaming: false,
        })
        .unwrap();

        // Next sequence should be 2
        let seq2 = db.get_next_message_sequence(&session_id).unwrap();
        assert_eq!(seq2, 2);

        // Insert another message
        db.insert_message(&NewAgentCodingSessionMessage {
            id: "msg-2".to_string(),
            session_id: session_id.clone(),
            content: "message 2".to_string(),
            sequence_number: seq2,
            is_streaming: false,
        })
        .unwrap();

        // Next sequence should be 3
        let seq3 = db.get_next_message_sequence(&session_id).unwrap();
        assert_eq!(seq3, 3);

        // Messages should be ordered by sequence
        let messages = db.list_messages_for_session(&session_id).unwrap();
        assert_eq!(messages.len(), 2);
        assert_eq!(messages[0].sequence_number, 1);
        assert_eq!(messages[1].sequence_number, 2);
    }

    #[test]
    fn test_session_touch() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        let original = db.get_session(&session_id).unwrap().unwrap();
        let original_time = original.last_accessed_at;

        // Small delay to ensure time difference
        std::thread::sleep(std::time::Duration::from_millis(10));

        // Touch session
        assert!(db.touch_session(&session_id).unwrap());

        let updated = db.get_session(&session_id).unwrap().unwrap();
        assert!(updated.last_accessed_at >= original_time);

        // Touch non-existent session returns false
        assert!(!db.touch_session("nonexistent").unwrap());
    }

    #[test]
    fn test_session_secret_crud() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        // Initially no secret exists
        assert!(!db.has_session_secret(&session_id).unwrap());
        assert!(db.get_session_secret(&session_id).unwrap().is_none());

        // Store a secret
        let secret = NewSessionSecret {
            session_id: session_id.clone(),
            encrypted_secret: vec![1, 2, 3, 4, 5],
            nonce: vec![10, 20, 30],
        };
        db.set_session_secret(&secret).unwrap();

        // Secret exists now
        assert!(db.has_session_secret(&session_id).unwrap());

        // Get the secret
        let fetched = db.get_session_secret(&session_id).unwrap().unwrap();
        assert_eq!(fetched.session_id, session_id);
        assert_eq!(fetched.encrypted_secret, vec![1, 2, 3, 4, 5]);
        assert_eq!(fetched.nonce, vec![10, 20, 30]);

        // Update the secret (upsert)
        let updated_secret = NewSessionSecret {
            session_id: session_id.clone(),
            encrypted_secret: vec![6, 7, 8, 9, 10],
            nonce: vec![40, 50, 60],
        };
        db.set_session_secret(&updated_secret).unwrap();

        let fetched = db.get_session_secret(&session_id).unwrap().unwrap();
        assert_eq!(fetched.encrypted_secret, vec![6, 7, 8, 9, 10]);
        assert_eq!(fetched.nonce, vec![40, 50, 60]);

        // Delete the secret
        assert!(db.delete_session_secret(&session_id).unwrap());
        assert!(!db.has_session_secret(&session_id).unwrap());
        assert!(db.get_session_secret(&session_id).unwrap().is_none());

        // Deleting non-existent returns false
        assert!(!db.delete_session_secret(&session_id).unwrap());
    }

    #[test]
    fn test_session_secret_cascade_delete() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        // Store a secret
        let secret = NewSessionSecret {
            session_id: session_id.clone(),
            encrypted_secret: vec![1, 2, 3],
            nonce: vec![4, 5, 6],
        };
        db.set_session_secret(&secret).unwrap();
        assert!(db.has_session_secret(&session_id).unwrap());

        // Delete the session - secret should be cascade deleted
        db.delete_session(&session_id).unwrap();
        assert!(!db.has_session_secret(&session_id).unwrap());
    }

    #[test]
    fn test_update_session_claude_id() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        // Initially no claude_session_id
        let session = db.get_session(&session_id).unwrap().unwrap();
        assert!(session.claude_session_id.is_none());

        // Update claude session ID
        assert!(db
            .update_session_claude_id(&session_id, "claude-abc-123")
            .unwrap());
        let session = db.get_session(&session_id).unwrap().unwrap();
        assert_eq!(
            session.claude_session_id,
            Some("claude-abc-123".to_string())
        );

        // Overwrite with new ID
        assert!(db
            .update_session_claude_id(&session_id, "claude-def-456")
            .unwrap());
        let session = db.get_session(&session_id).unwrap().unwrap();
        assert_eq!(
            session.claude_session_id,
            Some("claude-def-456".to_string())
        );

        // Non-existent session returns false
        assert!(!db
            .update_session_claude_id("nonexistent", "claude-xyz")
            .unwrap());
    }

    #[test]
    fn test_supabase_message_outbox_lifecycle() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        // Insert messages (outbox has FK to messages)
        for i in 1..=3 {
            db.insert_message(&NewAgentCodingSessionMessage {
                id: format!("msg-{}", i),
                session_id: session_id.clone(),
                content: format!("content {}", i),
                sequence_number: i,
                is_streaming: false,
            })
            .unwrap();
        }

        // Insert into Supabase outbox
        db.insert_supabase_message_outbox("msg-1").unwrap();
        db.insert_supabase_message_outbox("msg-2").unwrap();
        db.insert_supabase_message_outbox("msg-3").unwrap();

        // Get pending messages (joined with message content)
        let pending = db.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending.len(), 3);
        assert_eq!(pending[0].message_id, "msg-1");
        assert_eq!(pending[0].session_id, session_id);
        assert_eq!(pending[0].content, "content 1");
        assert_eq!(pending[0].retry_count, 0);
        assert!(pending[0].last_error.is_none());

        // Mark first two as sent
        db.mark_supabase_messages_sent(&["msg-1".to_string(), "msg-2".to_string()])
            .unwrap();
        let pending = db.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].message_id, "msg-3");
    }

    #[test]
    fn test_supabase_message_outbox_failure_tracking() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        db.insert_message(&NewAgentCodingSessionMessage {
            id: "msg-1".to_string(),
            session_id: session_id.clone(),
            content: "content".to_string(),
            sequence_number: 1,
            is_streaming: false,
        })
        .unwrap();

        db.insert_supabase_message_outbox("msg-1").unwrap();

        // Mark as failed
        db.mark_supabase_messages_failed(&["msg-1".to_string()], "connection timeout")
            .unwrap();

        let pending = db.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].retry_count, 1);
        assert_eq!(pending[0].last_error.as_deref(), Some("connection timeout"));
        assert!(pending[0].last_attempt_at.is_some());

        // Mark as failed again - retry count should increment
        db.mark_supabase_messages_failed(&["msg-1".to_string()], "connection refused")
            .unwrap();

        let pending = db.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending[0].retry_count, 2);
        assert_eq!(pending[0].last_error.as_deref(), Some("connection refused"));
    }

    #[test]
    fn test_supabase_message_outbox_delete() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        for i in 1..=2 {
            db.insert_message(&NewAgentCodingSessionMessage {
                id: format!("msg-{}", i),
                session_id: session_id.clone(),
                content: format!("content {}", i),
                sequence_number: i,
                is_streaming: false,
            })
            .unwrap();
            db.insert_supabase_message_outbox(&format!("msg-{}", i))
                .unwrap();
        }

        let pending = db.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending.len(), 2);

        // Delete one entry
        db.delete_supabase_message_outbox(&["msg-1".to_string()])
            .unwrap();
        let pending = db.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].message_id, "msg-2");
    }

    #[test]
    fn test_supabase_message_outbox_duplicate_insert_ignored() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        db.insert_message(&NewAgentCodingSessionMessage {
            id: "msg-1".to_string(),
            session_id: session_id.clone(),
            content: "content".to_string(),
            sequence_number: 1,
            is_streaming: false,
        })
        .unwrap();

        // Insert twice - second should be silently ignored
        db.insert_supabase_message_outbox("msg-1").unwrap();
        db.insert_supabase_message_outbox("msg-1").unwrap();

        let pending = db.get_pending_supabase_messages(10).unwrap();
        assert_eq!(pending.len(), 1);
    }

    #[test]
    fn test_supabase_message_outbox_empty_operations() {
        let db = create_test_db();

        // Empty mark_sent should be a no-op
        db.mark_supabase_messages_sent(&[]).unwrap();

        // Empty mark_failed should be a no-op
        db.mark_supabase_messages_failed(&[], "error").unwrap();

        // Empty delete should be a no-op
        db.delete_supabase_message_outbox(&[]).unwrap();
    }

    #[test]
    fn test_supabase_message_outbox_limit() {
        let db = create_test_db();
        let (_, session_id) = setup_test_repo_and_session(&db);

        for i in 1..=5 {
            db.insert_message(&NewAgentCodingSessionMessage {
                id: format!("msg-{}", i),
                session_id: session_id.clone(),
                content: format!("content {}", i),
                sequence_number: i,
                is_streaming: false,
            })
            .unwrap();
            db.insert_supabase_message_outbox(&format!("msg-{}", i))
                .unwrap();
        }

        // Request only 2 pending messages
        let pending = db.get_pending_supabase_messages(2).unwrap();
        assert_eq!(pending.len(), 2);

        // Request more than available
        let pending = db.get_pending_supabase_messages(100).unwrap();
        assert_eq!(pending.len(), 5);
    }
}
