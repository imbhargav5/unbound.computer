//! Standalone query functions that work with any Connection.
//!
//! These functions are designed to work with both single connections and pooled connections.
//! Each function takes a `&Connection` as its first parameter.

use crate::{
    AgentCodingSession, AgentCodingSessionMessage, AgentCodingSessionState, AgentStatus,
    DatabaseError, DatabaseResult, NewAgentCodingSession, NewAgentCodingSessionMessage,
    NewRepository, NewSessionSecret, Repository, SessionSecret, SessionStatus,
    SupabaseMessageOutboxPending, UserSetting,
};
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use tracing::debug;

// ==========================================
// Repositories
// ==========================================

/// Insert a new repository.
pub fn insert_repository(conn: &Connection, repo: &NewRepository) -> DatabaseResult<Repository> {
    let now = Utc::now().to_rfc3339();
    conn.execute(
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
    get_repository(conn, &repo.id)?
        .ok_or_else(|| DatabaseError::NotFound("Repository not found after insert".to_string()))
}

/// Get a repository by ID.
pub fn get_repository(conn: &Connection, id: &str) -> DatabaseResult<Option<Repository>> {
    let mut stmt = conn.prepare_cached(
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
pub fn get_repository_by_path(conn: &Connection, path: &str) -> DatabaseResult<Option<Repository>> {
    let mut stmt = conn.prepare_cached(
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
pub fn list_repositories(conn: &Connection) -> DatabaseResult<Vec<Repository>> {
    let mut stmt = conn.prepare_cached(
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
pub fn delete_repository(conn: &Connection, id: &str) -> DatabaseResult<bool> {
    let count = conn.execute("DELETE FROM repositories WHERE id = ?1", params![id])?;
    Ok(count > 0)
}

/// Update repository settings.
///
/// This updates the repository defaults stored in SQLite.
pub fn update_repository_settings(
    conn: &Connection,
    id: &str,
    sessions_path: Option<&str>,
    default_branch: Option<&str>,
    default_remote: Option<&str>,
) -> DatabaseResult<bool> {
    let now = Utc::now().to_rfc3339();
    let count = conn.execute(
        "UPDATE repositories
         SET sessions_path = ?1, default_branch = ?2, default_remote = ?3, updated_at = ?4
         WHERE id = ?5",
        params![sessions_path, default_branch, default_remote, now, id],
    )?;
    Ok(count > 0)
}

// ==========================================
// Sessions
// ==========================================

/// Insert a new session.
pub fn insert_session(
    conn: &Connection,
    session: &NewAgentCodingSession,
) -> DatabaseResult<AgentCodingSession> {
    let now = Utc::now().to_rfc3339();
    conn.execute(
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
    get_session(conn, &session.id)?
        .ok_or_else(|| DatabaseError::NotFound("Session not found after insert".to_string()))
}

/// Get a session by ID.
pub fn get_session(conn: &Connection, id: &str) -> DatabaseResult<Option<AgentCodingSession>> {
    let mut stmt = conn.prepare_cached(
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
    conn: &Connection,
    repository_id: &str,
) -> DatabaseResult<Vec<AgentCodingSession>> {
    let mut stmt = conn.prepare_cached(
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
pub fn update_session_title(conn: &Connection, id: &str, title: &str) -> DatabaseResult<bool> {
    let now = Utc::now().to_rfc3339();
    let count = conn.execute(
        "UPDATE agent_coding_sessions SET title = ?1, updated_at = ?2 WHERE id = ?3",
        params![title, now, id],
    )?;
    Ok(count > 0)
}

/// Update session last accessed time.
pub fn touch_session(conn: &Connection, id: &str) -> DatabaseResult<bool> {
    let now = Utc::now().to_rfc3339();
    let count = conn.execute(
        "UPDATE agent_coding_sessions SET last_accessed_at = ?1, updated_at = ?1 WHERE id = ?2",
        params![now, id],
    )?;
    Ok(count > 0)
}

/// Delete a session by ID.
pub fn delete_session(conn: &Connection, id: &str) -> DatabaseResult<bool> {
    let count = conn.execute(
        "DELETE FROM agent_coding_sessions WHERE id = ?1",
        params![id],
    )?;
    Ok(count > 0)
}

/// Update the Claude session ID for a session.
pub fn update_session_claude_id(
    conn: &Connection,
    id: &str,
    claude_session_id: &str,
) -> DatabaseResult<bool> {
    let now = Utc::now().to_rfc3339();
    let count = conn.execute(
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
    conn: &Connection,
    session_id: &str,
) -> DatabaseResult<AgentCodingSessionState> {
    if let Some(state) = get_session_state(conn, session_id)? {
        return Ok(state);
    }

    let now_ms = now_timestamp_ms();
    conn.execute(
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

    get_session_state(conn, session_id)?
        .ok_or_else(|| DatabaseError::NotFound("Session state not found after insert".to_string()))
}

/// Get session state.
pub fn get_session_state(
    conn: &Connection,
    session_id: &str,
) -> DatabaseResult<Option<AgentCodingSessionState>> {
    let mut stmt = conn.prepare_cached(
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
    conn: &Connection,
    session_id: &str,
    status: AgentStatus,
) -> DatabaseResult<bool> {
    let now_ms = now_timestamp_ms();
    let count = conn.execute(
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
pub fn insert_message(
    conn: &Connection,
    message: &NewAgentCodingSessionMessage,
) -> DatabaseResult<()> {
    let now = Utc::now().to_rfc3339();
    conn.execute(
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
pub fn get_message(
    conn: &Connection,
    id: &str,
) -> DatabaseResult<Option<AgentCodingSessionMessage>> {
    let mut stmt = conn.prepare_cached(
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
    conn: &Connection,
    session_id: &str,
) -> DatabaseResult<Vec<AgentCodingSessionMessage>> {
    let mut stmt = conn.prepare_cached(
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
pub fn get_next_message_sequence(conn: &Connection, session_id: &str) -> DatabaseResult<i64> {
    let max: Option<i64> = conn.query_row(
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
pub fn insert_supabase_message_outbox(conn: &Connection, message_id: &str) -> DatabaseResult<()> {
    conn.execute(
        "INSERT OR IGNORE INTO agent_coding_session_message_supabase_outbox (message_id)
         VALUES (?1)",
        params![message_id],
    )?;
    Ok(())
}

/// Get pending Supabase message outbox entries (joined with message content).
pub fn get_pending_supabase_messages(
    conn: &Connection,
    limit: usize,
) -> DatabaseResult<Vec<SupabaseMessageOutboxPending>> {
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
pub fn mark_supabase_messages_sent(
    conn: &Connection,
    message_ids: &[String],
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
         SET sent_at = ?1, last_error = NULL
         WHERE message_id IN ({})",
        placeholders
    );

    let mut params_vec: Vec<&dyn rusqlite::ToSql> = Vec::with_capacity(message_ids.len() + 1);
    params_vec.push(&now);
    for id in message_ids {
        params_vec.push(id);
    }

    conn.execute(&sql, params_vec.as_slice())?;
    Ok(())
}

/// Mark messages as failed to sync (increments retry count).
pub fn mark_supabase_messages_failed(
    conn: &Connection,
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

    conn.execute(&sql, params_vec.as_slice())?;
    Ok(())
}

/// Delete messages from the Supabase outbox.
pub fn delete_supabase_message_outbox(
    conn: &Connection,
    message_ids: &[String],
) -> DatabaseResult<()> {
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

    conn.execute(&sql, params_vec.as_slice())?;
    Ok(())
}

// ==========================================
// User Settings
// ==========================================

/// Get a user setting.
pub fn get_setting(conn: &Connection, key: &str) -> DatabaseResult<Option<UserSetting>> {
    let mut stmt = conn
        .prepare("SELECT key, value, value_type, updated_at FROM user_settings WHERE key = ?1")?;

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
pub fn set_setting(
    conn: &Connection,
    key: &str,
    value: &str,
    value_type: &str,
) -> DatabaseResult<()> {
    let now = Utc::now().to_rfc3339();
    conn.execute(
        "INSERT INTO user_settings (key, value, value_type, updated_at)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(key) DO UPDATE SET value = ?2, value_type = ?3, updated_at = ?4",
        params![key, value, value_type, now],
    )?;
    Ok(())
}

/// Delete a user setting.
pub fn delete_setting(conn: &Connection, key: &str) -> DatabaseResult<bool> {
    let count = conn.execute("DELETE FROM user_settings WHERE key = ?1", params![key])?;
    Ok(count > 0)
}

// ==========================================
// Session Secrets
// ==========================================

/// Get a session secret by session ID.
pub fn get_session_secret(
    conn: &Connection,
    session_id: &str,
) -> DatabaseResult<Option<SessionSecret>> {
    let mut stmt = conn.prepare_cached(
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
pub fn set_session_secret(conn: &Connection, secret: &NewSessionSecret) -> DatabaseResult<()> {
    let now = Utc::now().to_rfc3339();
    conn.execute(
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
pub fn delete_session_secret(conn: &Connection, session_id: &str) -> DatabaseResult<bool> {
    let count = conn.execute(
        "DELETE FROM session_secrets WHERE session_id = ?1",
        params![session_id],
    )?;
    Ok(count > 0)
}

/// Check if a session secret exists.
pub fn has_session_secret(conn: &Connection, session_id: &str) -> DatabaseResult<bool> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM session_secrets WHERE session_id = ?1",
        params![session_id],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}

// ==========================================
// Helpers
// ==========================================

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
    use crate::{
        migrations, NewAgentCodingSession, NewAgentCodingSessionMessage, NewRepository,
        NewSessionSecret,
    };
    use chrono::Datelike;

    fn setup_conn() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        migrations::run_migrations(&conn).unwrap();
        conn
    }

    fn insert_test_repo(conn: &Connection) -> String {
        let id = "repo-1".to_string();
        insert_repository(
            conn,
            &NewRepository {
                id: id.clone(),
                path: "/test/repo".to_string(),
                name: "test-repo".to_string(),
                is_git_repository: true,
                sessions_path: None,
                default_branch: Some("main".to_string()),
                default_remote: Some("origin".to_string()),
            },
        )
        .unwrap();
        id
    }

    fn insert_test_session(conn: &Connection, repo_id: &str) -> String {
        let id = "session-1".to_string();
        insert_session(
            conn,
            &NewAgentCodingSession {
                id: id.clone(),
                repository_id: repo_id.to_string(),
                title: "Test Session".to_string(),
                claude_session_id: None,
                is_worktree: false,
                worktree_path: None,
            },
        )
        .unwrap();
        id
    }

    // =========================================================================
    // Repository queries
    // =========================================================================

    #[test]
    fn repository_insert_and_get() {
        let conn = setup_conn();
        let repo = insert_repository(
            &conn,
            &NewRepository {
                id: "r1".to_string(),
                path: "/path/to/repo".to_string(),
                name: "my-repo".to_string(),
                is_git_repository: true,
                sessions_path: Some("/sessions".to_string()),
                default_branch: Some("main".to_string()),
                default_remote: Some("origin".to_string()),
            },
        )
        .unwrap();

        assert_eq!(repo.id, "r1");
        assert_eq!(repo.path, "/path/to/repo");
        assert_eq!(repo.name, "my-repo");
        assert!(repo.is_git_repository);
        assert_eq!(repo.sessions_path, Some("/sessions".to_string()));
        assert_eq!(repo.default_branch, Some("main".to_string()));
        assert_eq!(repo.default_remote, Some("origin".to_string()));
    }

    #[test]
    fn repository_get_by_path() {
        let conn = setup_conn();
        insert_test_repo(&conn);

        let found = get_repository_by_path(&conn, "/test/repo").unwrap();
        assert!(found.is_some());
        assert_eq!(found.unwrap().id, "repo-1");

        let missing = get_repository_by_path(&conn, "/nonexistent").unwrap();
        assert!(missing.is_none());
    }

    #[test]
    fn repository_list_ordered_by_last_accessed() {
        let conn = setup_conn();

        insert_repository(
            &conn,
            &NewRepository {
                id: "r1".into(),
                path: "/a".into(),
                name: "a".into(),
                is_git_repository: false,
                sessions_path: None,
                default_branch: None,
                default_remote: None,
            },
        )
        .unwrap();

        insert_repository(
            &conn,
            &NewRepository {
                id: "r2".into(),
                path: "/b".into(),
                name: "b".into(),
                is_git_repository: false,
                sessions_path: None,
                default_branch: None,
                default_remote: None,
            },
        )
        .unwrap();

        let repos = list_repositories(&conn).unwrap();
        assert_eq!(repos.len(), 2);
        // Most recently inserted should be first (DESC order)
        assert_eq!(repos[0].id, "r2");
    }

    #[test]
    fn repository_delete() {
        let conn = setup_conn();
        insert_test_repo(&conn);

        assert!(delete_repository(&conn, "repo-1").unwrap());
        assert!(get_repository(&conn, "repo-1").unwrap().is_none());
        // Deleting again returns false
        assert!(!delete_repository(&conn, "repo-1").unwrap());
    }

    #[test]
    fn repository_update_settings() {
        let conn = setup_conn();
        insert_test_repo(&conn);

        // Set all settings.
        assert!(update_repository_settings(
            &conn,
            "repo-1",
            Some("/tmp/sessions"),
            Some("main"),
            Some("origin"),
        )
        .unwrap());

        let updated = get_repository(&conn, "repo-1").unwrap().unwrap();
        assert_eq!(updated.sessions_path, Some("/tmp/sessions".to_string()));
        assert_eq!(updated.default_branch, Some("main".to_string()));
        assert_eq!(updated.default_remote, Some("origin".to_string()));

        // Clear settings via NULL updates.
        assert!(update_repository_settings(&conn, "repo-1", None, None, None).unwrap());

        let cleared = get_repository(&conn, "repo-1").unwrap().unwrap();
        assert_eq!(cleared.sessions_path, None);
        assert_eq!(cleared.default_branch, None);
        assert_eq!(cleared.default_remote, None);

        // Missing repository returns false.
        assert!(!update_repository_settings(&conn, "missing-repo", None, None, None).unwrap());
    }

    // =========================================================================
    // Session queries
    // =========================================================================

    #[test]
    fn session_insert_and_get() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);

        let session = insert_session(
            &conn,
            &NewAgentCodingSession {
                id: "s1".into(),
                repository_id: repo_id,
                title: "My Session".into(),
                claude_session_id: Some("claude-xyz".into()),
                is_worktree: true,
                worktree_path: Some("/worktree".into()),
            },
        )
        .unwrap();

        assert_eq!(session.id, "s1");
        assert_eq!(session.title, "My Session");
        assert_eq!(session.claude_session_id, Some("claude-xyz".into()));
        assert!(session.is_worktree);
        assert_eq!(session.worktree_path, Some("/worktree".into()));
    }

    #[test]
    fn session_update_title() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        assert!(update_session_title(&conn, &session_id, "New Title").unwrap());
        let s = get_session(&conn, &session_id).unwrap().unwrap();
        assert_eq!(s.title, "New Title");

        // Non-existent returns false
        assert!(!update_session_title(&conn, "nope", "title").unwrap());
    }

    #[test]
    fn session_update_claude_id() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        assert!(update_session_claude_id(&conn, &session_id, "claude-abc").unwrap());
        let s = get_session(&conn, &session_id).unwrap().unwrap();
        assert_eq!(s.claude_session_id, Some("claude-abc".into()));
    }

    #[test]
    fn session_touch_updates_last_accessed() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        let before = get_session(&conn, &session_id)
            .unwrap()
            .unwrap()
            .last_accessed_at;
        std::thread::sleep(std::time::Duration::from_millis(10));
        assert!(touch_session(&conn, &session_id).unwrap());
        let after = get_session(&conn, &session_id)
            .unwrap()
            .unwrap()
            .last_accessed_at;
        assert!(after >= before);
    }

    #[test]
    fn session_list_for_repository() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);

        insert_session(
            &conn,
            &NewAgentCodingSession {
                id: "s1".into(),
                repository_id: repo_id.clone(),
                title: "First".into(),
                claude_session_id: None,
                is_worktree: false,
                worktree_path: None,
            },
        )
        .unwrap();
        insert_session(
            &conn,
            &NewAgentCodingSession {
                id: "s2".into(),
                repository_id: repo_id.clone(),
                title: "Second".into(),
                claude_session_id: None,
                is_worktree: false,
                worktree_path: None,
            },
        )
        .unwrap();

        let sessions = list_sessions_for_repository(&conn, &repo_id).unwrap();
        assert_eq!(sessions.len(), 2);

        // No sessions for other repo
        let empty = list_sessions_for_repository(&conn, "other-repo").unwrap();
        assert!(empty.is_empty());
    }

    #[test]
    fn session_delete() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        assert!(delete_session(&conn, &session_id).unwrap());
        assert!(get_session(&conn, &session_id).unwrap().is_none());
        assert!(!delete_session(&conn, &session_id).unwrap());
    }

    // =========================================================================
    // Session state queries
    // =========================================================================

    #[test]
    fn session_state_get_or_create() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        // Should not exist yet
        assert!(get_session_state(&conn, &session_id).unwrap().is_none());

        // get_or_create creates it
        let state = get_or_create_session_state(&conn, &session_id).unwrap();
        assert_eq!(state.agent_status, crate::AgentStatus::Idle);

        // Calling again returns existing
        let state2 = get_or_create_session_state(&conn, &session_id).unwrap();
        assert_eq!(state2.agent_status, crate::AgentStatus::Idle);
    }

    #[test]
    fn session_state_update_agent_status() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);
        get_or_create_session_state(&conn, &session_id).unwrap();

        assert!(update_agent_status(&conn, &session_id, crate::AgentStatus::Running).unwrap());
        let state = get_session_state(&conn, &session_id).unwrap().unwrap();
        assert_eq!(state.agent_status, crate::AgentStatus::Running);

        // Non-existent returns false
        assert!(!update_agent_status(&conn, "nope", crate::AgentStatus::Idle).unwrap());
    }

    // =========================================================================
    // Message queries
    // =========================================================================

    #[test]
    fn message_insert_get_list() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        insert_message(
            &conn,
            &NewAgentCodingSessionMessage {
                id: "m1".into(),
                session_id: session_id.clone(),
                content: r#"{"role":"user","text":"hello"}"#.into(),
                sequence_number: 1,
                is_streaming: false,
            },
        )
        .unwrap();

        let msg = get_message(&conn, "m1").unwrap().unwrap();
        assert_eq!(msg.content, r#"{"role":"user","text":"hello"}"#);
        assert_eq!(msg.sequence_number, 1);
        assert!(!msg.is_streaming);

        let msgs = list_messages_for_session(&conn, &session_id).unwrap();
        assert_eq!(msgs.len(), 1);

        assert!(get_message(&conn, "nonexistent").unwrap().is_none());
    }

    #[test]
    fn message_sequence_numbers() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        assert_eq!(get_next_message_sequence(&conn, &session_id).unwrap(), 1);

        insert_message(
            &conn,
            &NewAgentCodingSessionMessage {
                id: "m1".into(),
                session_id: session_id.clone(),
                content: "a".into(),
                sequence_number: 1,
                is_streaming: false,
            },
        )
        .unwrap();

        assert_eq!(get_next_message_sequence(&conn, &session_id).unwrap(), 2);

        insert_message(
            &conn,
            &NewAgentCodingSessionMessage {
                id: "m2".into(),
                session_id: session_id.clone(),
                content: "b".into(),
                sequence_number: 5,
                is_streaming: false,
            },
        )
        .unwrap();

        // Next after max(5) = 6
        assert_eq!(get_next_message_sequence(&conn, &session_id).unwrap(), 6);
    }

    // =========================================================================
    // Supabase message outbox queries
    // =========================================================================

    #[test]
    fn supabase_outbox_insert_and_get_pending() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        insert_message(
            &conn,
            &NewAgentCodingSessionMessage {
                id: "m1".into(),
                session_id: session_id.clone(),
                content: "hello world".into(),
                sequence_number: 1,
                is_streaming: false,
            },
        )
        .unwrap();

        insert_supabase_message_outbox(&conn, "m1").unwrap();

        let pending = get_pending_supabase_messages(&conn, 10).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].message_id, "m1");
        assert_eq!(pending[0].session_id, session_id);
        assert_eq!(pending[0].content, "hello world");
        assert_eq!(pending[0].sequence_number, 1);
        assert_eq!(pending[0].retry_count, 0);
        assert!(pending[0].last_error.is_none());
    }

    #[test]
    fn supabase_outbox_mark_sent_removes_from_pending() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        for i in 1..=3 {
            insert_message(
                &conn,
                &NewAgentCodingSessionMessage {
                    id: format!("m{i}"),
                    session_id: session_id.clone(),
                    content: format!("c{i}"),
                    sequence_number: i,
                    is_streaming: false,
                },
            )
            .unwrap();
            insert_supabase_message_outbox(&conn, &format!("m{i}")).unwrap();
        }

        mark_supabase_messages_sent(&conn, &["m1".into(), "m2".into()]).unwrap();
        let pending = get_pending_supabase_messages(&conn, 10).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].message_id, "m3");
    }

    #[test]
    fn supabase_outbox_mark_failed_increments_retry() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        insert_message(
            &conn,
            &NewAgentCodingSessionMessage {
                id: "m1".into(),
                session_id: session_id.clone(),
                content: "c".into(),
                sequence_number: 1,
                is_streaming: false,
            },
        )
        .unwrap();
        insert_supabase_message_outbox(&conn, "m1").unwrap();

        mark_supabase_messages_failed(&conn, &["m1".into()], "timeout").unwrap();
        let p = get_pending_supabase_messages(&conn, 10).unwrap();
        assert_eq!(p[0].retry_count, 1);
        assert_eq!(p[0].last_error.as_deref(), Some("timeout"));

        mark_supabase_messages_failed(&conn, &["m1".into()], "refused").unwrap();
        let p = get_pending_supabase_messages(&conn, 10).unwrap();
        assert_eq!(p[0].retry_count, 2);
        assert_eq!(p[0].last_error.as_deref(), Some("refused"));
    }

    #[test]
    fn supabase_outbox_delete() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        for i in 1..=2 {
            insert_message(
                &conn,
                &NewAgentCodingSessionMessage {
                    id: format!("m{i}"),
                    session_id: session_id.clone(),
                    content: format!("c{i}"),
                    sequence_number: i,
                    is_streaming: false,
                },
            )
            .unwrap();
            insert_supabase_message_outbox(&conn, &format!("m{i}")).unwrap();
        }

        delete_supabase_message_outbox(&conn, &["m1".into()]).unwrap();
        let pending = get_pending_supabase_messages(&conn, 10).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].message_id, "m2");
    }

    #[test]
    fn supabase_outbox_empty_operations_are_noops() {
        let conn = setup_conn();
        mark_supabase_messages_sent(&conn, &[]).unwrap();
        mark_supabase_messages_failed(&conn, &[], "err").unwrap();
        delete_supabase_message_outbox(&conn, &[]).unwrap();
    }

    #[test]
    fn supabase_outbox_duplicate_insert_ignored() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        insert_message(
            &conn,
            &NewAgentCodingSessionMessage {
                id: "m1".into(),
                session_id: session_id.clone(),
                content: "c".into(),
                sequence_number: 1,
                is_streaming: false,
            },
        )
        .unwrap();

        insert_supabase_message_outbox(&conn, "m1").unwrap();
        insert_supabase_message_outbox(&conn, "m1").unwrap(); // should not error
        let pending = get_pending_supabase_messages(&conn, 10).unwrap();
        assert_eq!(pending.len(), 1);
    }

    #[test]
    fn supabase_outbox_limit_respected() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        for i in 1..=5 {
            insert_message(
                &conn,
                &NewAgentCodingSessionMessage {
                    id: format!("m{i}"),
                    session_id: session_id.clone(),
                    content: format!("c{i}"),
                    sequence_number: i,
                    is_streaming: false,
                },
            )
            .unwrap();
            insert_supabase_message_outbox(&conn, &format!("m{i}")).unwrap();
        }

        let batch = get_pending_supabase_messages(&conn, 2).unwrap();
        assert_eq!(batch.len(), 2);
    }

    // =========================================================================
    // Session secret queries
    // =========================================================================

    #[test]
    fn session_secret_crud() {
        let conn = setup_conn();
        let repo_id = insert_test_repo(&conn);
        let session_id = insert_test_session(&conn, &repo_id);

        assert!(!has_session_secret(&conn, &session_id).unwrap());
        assert!(get_session_secret(&conn, &session_id).unwrap().is_none());

        set_session_secret(
            &conn,
            &NewSessionSecret {
                session_id: session_id.clone(),
                encrypted_secret: vec![1, 2, 3],
                nonce: vec![10, 20],
            },
        )
        .unwrap();

        assert!(has_session_secret(&conn, &session_id).unwrap());
        let s = get_session_secret(&conn, &session_id).unwrap().unwrap();
        assert_eq!(s.encrypted_secret, vec![1, 2, 3]);
        assert_eq!(s.nonce, vec![10, 20]);

        // Upsert overwrites
        set_session_secret(
            &conn,
            &NewSessionSecret {
                session_id: session_id.clone(),
                encrypted_secret: vec![4, 5, 6],
                nonce: vec![30, 40],
            },
        )
        .unwrap();
        let s = get_session_secret(&conn, &session_id).unwrap().unwrap();
        assert_eq!(s.encrypted_secret, vec![4, 5, 6]);

        assert!(delete_session_secret(&conn, &session_id).unwrap());
        assert!(!has_session_secret(&conn, &session_id).unwrap());
        assert!(!delete_session_secret(&conn, &session_id).unwrap());
    }

    // =========================================================================
    // Settings queries
    // =========================================================================

    #[test]
    fn settings_crud() {
        let conn = setup_conn();

        assert!(get_setting(&conn, "theme").unwrap().is_none());

        set_setting(&conn, "theme", "dark", "string").unwrap();
        let s = get_setting(&conn, "theme").unwrap().unwrap();
        assert_eq!(s.value, "dark");
        assert_eq!(s.value_type, "string");

        // Upsert
        set_setting(&conn, "theme", "light", "string").unwrap();
        let s = get_setting(&conn, "theme").unwrap().unwrap();
        assert_eq!(s.value, "light");

        assert!(delete_setting(&conn, "theme").unwrap());
        assert!(get_setting(&conn, "theme").unwrap().is_none());
        assert!(!delete_setting(&conn, "theme").unwrap());
    }

    // =========================================================================
    // parse_datetime helper
    // =========================================================================

    #[test]
    fn parse_datetime_valid_rfc3339() {
        let dt = parse_datetime("2024-01-15T10:30:00+00:00".to_string());
        assert_eq!(dt.year(), 2024);
        assert_eq!(dt.month(), 1);
        assert_eq!(dt.day(), 15);
    }

    #[test]
    fn parse_datetime_invalid_falls_back_to_now() {
        let before = Utc::now();
        let dt = parse_datetime("not-a-date".to_string());
        let after = Utc::now();
        assert!(dt >= before && dt <= after);
    }
}
