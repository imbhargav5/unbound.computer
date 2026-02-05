//! Standalone query functions that work with any Connection.
//!
//! These functions are designed to work with both single connections and pooled connections.
//! Each function takes a `&Connection` as its first parameter.

use crate::{
    AgentCodingSession, AgentCodingSessionEventOutbox, AgentCodingSessionMessage,
    AgentCodingSessionState, AgentStatus, DatabaseError, DatabaseResult, NewAgentCodingSession,
    NewAgentCodingSessionMessage, NewOutboxEvent, NewRepository, NewSessionSecret, OutboxStatus,
    Repository, SessionSecret, SessionStatus, SupabaseMessageOutboxPending, UserSetting,
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

    let now = Utc::now().to_rfc3339();
    conn.execute(
        "INSERT INTO agent_coding_session_state (session_id, agent_status, updated_at)
         VALUES (?1, 'idle', ?2)",
        params![session_id, now],
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
        "SELECT session_id, agent_status, queued_commands, diff_summary, updated_at
         FROM agent_coding_session_state WHERE session_id = ?1",
    )?;

    let result = stmt.query_row(params![session_id], |row| {
        Ok(AgentCodingSessionState {
            session_id: row.get(0)?,
            agent_status: AgentStatus::from_str(&row.get::<_, String>(1)?),
            queued_commands: row.get(2)?,
            diff_summary: row.get(3)?,
            updated_at: parse_datetime(row.get::<_, String>(4)?),
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
    let now = Utc::now().to_rfc3339();
    let count = conn.execute(
        "UPDATE agent_coding_session_state SET agent_status = ?1, updated_at = ?2 WHERE session_id = ?3",
        params![status.as_str(), now, session_id],
    )?;
    Ok(count > 0)
}

// ==========================================
// Messages
// ==========================================

/// Insert a new message.
pub fn insert_message(conn: &Connection, message: &NewAgentCodingSessionMessage) -> DatabaseResult<()> {
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
// Outbox
// ==========================================

/// Insert a new outbox event.
pub fn insert_outbox_event(conn: &Connection, event: &NewOutboxEvent) -> DatabaseResult<()> {
    let now = Utc::now().to_rfc3339();
    conn.execute(
        "INSERT INTO agent_coding_session_event_outbox (event_id, session_id, sequence_number, message_id, status, created_at)
         VALUES (?1, ?2, ?3, ?4, 'pending', ?5)",
        params![
            event.event_id,
            event.session_id,
            event.sequence_number,
            event.message_id,
            now,
        ],
    )?;
    Ok(())
}

/// Get pending outbox events for a session (limited to batch size).
pub fn get_pending_outbox_events(
    conn: &Connection,
    session_id: &str,
    limit: usize,
) -> DatabaseResult<Vec<AgentCodingSessionEventOutbox>> {
    let mut stmt = conn.prepare_cached(
        "SELECT event_id, session_id, sequence_number, relay_send_batch_id, message_id, status, retry_count, last_error, created_at, sent_at, acked_at
         FROM agent_coding_session_event_outbox
         WHERE session_id = ?1 AND status = 'pending'
         ORDER BY sequence_number ASC
         LIMIT ?2",
    )?;

    let events = stmt
        .query_map(params![session_id, limit as i64], |row| {
            Ok(AgentCodingSessionEventOutbox {
                event_id: row.get(0)?,
                session_id: row.get(1)?,
                sequence_number: row.get(2)?,
                relay_send_batch_id: row.get(3)?,
                message_id: row.get(4)?,
                status: OutboxStatus::from_str(&row.get::<_, String>(5)?),
                retry_count: row.get(6)?,
                last_error: row.get(7)?,
                created_at: parse_datetime(row.get::<_, String>(8)?),
                sent_at: row.get::<_, Option<String>>(9)?.map(parse_datetime),
                acked_at: row.get::<_, Option<String>>(10)?.map(parse_datetime),
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(events)
}

/// Mark outbox events as sent with a batch ID.
pub fn mark_outbox_events_sent(
    conn: &Connection,
    event_ids: &[String],
    batch_id: &str,
) -> DatabaseResult<()> {
    let now = Utc::now().to_rfc3339();
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

/// Mark outbox events as acknowledged by batch ID.
pub fn mark_outbox_batch_acked(conn: &Connection, batch_id: &str) -> DatabaseResult<usize> {
    let now = Utc::now().to_rfc3339();
    let count = conn.execute(
        "UPDATE agent_coding_session_event_outbox
         SET status = 'acked', acked_at = ?1
         WHERE relay_send_batch_id = ?2",
        params![now, batch_id],
    )?;
    Ok(count)
}

/// Reset sent events to pending (for crash recovery).
pub fn reset_sent_events_to_pending(conn: &Connection, session_id: &str) -> DatabaseResult<usize> {
    let count = conn.execute(
        "UPDATE agent_coding_session_event_outbox
         SET status = 'pending', relay_send_batch_id = NULL, sent_at = NULL
         WHERE session_id = ?1 AND status = 'sent'",
        params![session_id],
    )?;
    Ok(count)
}

/// Get the next outbox sequence number for a session.
pub fn get_next_outbox_sequence(conn: &Connection, session_id: &str) -> DatabaseResult<i64> {
    let max: Option<i64> = conn.query_row(
        "SELECT MAX(sequence_number) FROM agent_coding_session_event_outbox WHERE session_id = ?1",
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
pub fn mark_supabase_messages_sent(conn: &Connection, message_ids: &[String]) -> DatabaseResult<()> {
    if message_ids.is_empty() {
        return Ok(());
    }
    let now = Utc::now().to_rfc3339();
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
    let placeholders = std::iter::repeat("?").take(message_ids.len()).collect::<Vec<_>>().join(", ");
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
    let mut stmt =
        conn.prepare("SELECT key, value, value_type, updated_at FROM user_settings WHERE key = ?1")?;

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
        params![secret.session_id, secret.encrypted_secret, secret.nonce, now,],
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
