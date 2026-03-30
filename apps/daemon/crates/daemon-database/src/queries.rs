//! Standalone query functions that work with any Connection.
//!
//! These functions are designed to work with both single connections and pooled connections.
//! Each function takes a `&Connection` as its first parameter.

use crate::{
    AgentCodingSession, AgentCodingSessionMessage, AgentCodingSessionState, AgentStatus,
    DatabaseError, DatabaseResult, NewAgentCodingSession, NewAgentCodingSessionMessage,
    NewRepository, NewSessionSecret, Repository, SessionSecret, SessionStatus, UserSetting,
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
        "INSERT INTO local_repositories (
            id, path, name, machine_id, space_id, last_accessed_at, added_at, is_git_repository,
            sessions_path, default_branch, default_remote, created_at, updated_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7, ?8, ?9, ?10, ?6, ?6)",
        params![
            repo.id,
            repo.path,
            repo.name,
            repo.machine_id,
            repo.space_id,
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
        "SELECT id, path, name, machine_id, space_id, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
         FROM local_repositories WHERE id = ?1",
    )?;

    let result = stmt.query_row(params![id], |row| {
        Ok(Repository {
            id: row.get(0)?,
            path: row.get(1)?,
            name: row.get(2)?,
            machine_id: row.get(3)?,
            space_id: row.get(4)?,
            last_accessed_at: parse_datetime(row.get::<_, String>(5)?),
            added_at: parse_datetime(row.get::<_, String>(6)?),
            is_git_repository: row.get(7)?,
            sessions_path: row.get(8)?,
            default_branch: row.get(9)?,
            default_remote: row.get(10)?,
            created_at: parse_datetime(row.get::<_, String>(11)?),
            updated_at: parse_datetime(row.get::<_, String>(12)?),
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
        "SELECT id, path, name, machine_id, space_id, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
         FROM local_repositories WHERE path = ?1",
    )?;

    let result = stmt.query_row(params![path], |row| {
        Ok(Repository {
            id: row.get(0)?,
            path: row.get(1)?,
            name: row.get(2)?,
            machine_id: row.get(3)?,
            space_id: row.get(4)?,
            last_accessed_at: parse_datetime(row.get::<_, String>(5)?),
            added_at: parse_datetime(row.get::<_, String>(6)?),
            is_git_repository: row.get(7)?,
            sessions_path: row.get(8)?,
            default_branch: row.get(9)?,
            default_remote: row.get(10)?,
            created_at: parse_datetime(row.get::<_, String>(11)?),
            updated_at: parse_datetime(row.get::<_, String>(12)?),
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
        "SELECT id, path, name, machine_id, space_id, last_accessed_at, added_at, is_git_repository, sessions_path, default_branch, default_remote, created_at, updated_at
         FROM local_repositories ORDER BY last_accessed_at DESC",
    )?;

    let repos = stmt
        .query_map([], |row| {
            Ok(Repository {
                id: row.get(0)?,
                path: row.get(1)?,
                name: row.get(2)?,
                machine_id: row.get(3)?,
                space_id: row.get(4)?,
                last_accessed_at: parse_datetime(row.get::<_, String>(5)?),
                added_at: parse_datetime(row.get::<_, String>(6)?),
                is_git_repository: row.get(7)?,
                sessions_path: row.get(8)?,
                default_branch: row.get(9)?,
                default_remote: row.get(10)?,
                created_at: parse_datetime(row.get::<_, String>(11)?),
                updated_at: parse_datetime(row.get::<_, String>(12)?),
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(repos)
}

/// Delete a repository by ID.
pub fn delete_repository(conn: &Connection, id: &str) -> DatabaseResult<bool> {
    let count = conn.execute("DELETE FROM local_repositories WHERE id = ?1", params![id])?;
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
        "UPDATE local_repositories
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
        "INSERT INTO local_llm_conversations (
            id, repository_id, machine_id, space_id, title, agent_name, issue_id,
            issue_title, issue_url, provider, provider_session_id, claude_session_id, status,
            is_worktree, worktree_path, created_at, last_accessed_at, updated_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, 'active', ?13, ?14, ?15, ?15, ?15)",
        params![
            session.id,
            session.repository_id,
            session.machine_id,
            session.space_id,
            session.title,
            session.agent_name,
            session.issue_id,
            session.issue_title,
            session.issue_url,
            session.provider,
            session.provider_session_id,
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
        "SELECT id, repository_id, machine_id, space_id, title, agent_name, issue_id, issue_title, issue_url, provider, provider_session_id, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
         FROM local_llm_conversations WHERE id = ?1",
    )?;

    let result = stmt.query_row(params![id], |row| {
            Ok(AgentCodingSession {
                id: row.get(0)?,
                repository_id: row.get(1)?,
                machine_id: row.get(2)?,
                space_id: row.get(3)?,
                title: row.get(4)?,
                agent_name: row.get(5)?,
                issue_id: row.get(6)?,
                issue_title: row.get(7)?,
                issue_url: row.get(8)?,
                provider: row.get(9)?,
                provider_session_id: row.get(10)?,
                claude_session_id: row.get(11)?,
                status: SessionStatus::from_str(&row.get::<_, String>(12)?),
                is_worktree: row.get(13)?,
                worktree_path: row.get(14)?,
                created_at: parse_datetime(row.get::<_, String>(15)?),
                last_accessed_at: parse_datetime(row.get::<_, String>(16)?),
                updated_at: parse_datetime(row.get::<_, String>(17)?),
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
        "SELECT id, repository_id, machine_id, space_id, title, agent_name, issue_id, issue_title, issue_url, provider, provider_session_id, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at
         FROM local_llm_conversations WHERE repository_id = ?1 ORDER BY last_accessed_at DESC",
    )?;

    let sessions = stmt
        .query_map(params![repository_id], |row| {
            Ok(AgentCodingSession {
                id: row.get(0)?,
                repository_id: row.get(1)?,
                machine_id: row.get(2)?,
                space_id: row.get(3)?,
                title: row.get(4)?,
                agent_name: row.get(5)?,
                issue_id: row.get(6)?,
                issue_title: row.get(7)?,
                issue_url: row.get(8)?,
                provider: row.get(9)?,
                provider_session_id: row.get(10)?,
                claude_session_id: row.get(11)?,
                status: SessionStatus::from_str(&row.get::<_, String>(12)?),
                is_worktree: row.get(13)?,
                worktree_path: row.get(14)?,
                created_at: parse_datetime(row.get::<_, String>(15)?),
                last_accessed_at: parse_datetime(row.get::<_, String>(16)?),
                updated_at: parse_datetime(row.get::<_, String>(17)?),
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(sessions)
}

/// Update session title.
pub fn update_session_title(conn: &Connection, id: &str, title: &str) -> DatabaseResult<bool> {
    let now = Utc::now().to_rfc3339();
    let count = conn.execute(
        "UPDATE local_llm_conversations SET title = ?1, updated_at = ?2 WHERE id = ?3",
        params![title, now, id],
    )?;
    Ok(count > 0)
}

/// Update session last accessed time.
pub fn touch_session(conn: &Connection, id: &str) -> DatabaseResult<bool> {
    let now = Utc::now().to_rfc3339();
    let count = conn.execute(
        "UPDATE local_llm_conversations SET last_accessed_at = ?1, updated_at = ?1 WHERE id = ?2",
        params![now, id],
    )?;
    Ok(count > 0)
}

/// Delete a session by ID.
pub fn delete_session(conn: &Connection, id: &str) -> DatabaseResult<bool> {
    let count = conn.execute(
        "DELETE FROM local_llm_conversations WHERE id = ?1",
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
        "UPDATE local_llm_conversations
         SET provider = 'claude',
             provider_session_id = ?1,
             claude_session_id = ?1,
             updated_at = ?2
         WHERE id = ?3",
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
        "INSERT INTO local_llm_conversation_state (session_id, state_json, updated_at_ms)
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
         FROM local_llm_conversation_state WHERE session_id = ?1",
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
        "UPDATE local_llm_conversation_state
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
        "INSERT INTO local_llm_conversation_messages (id, session_id, content, timestamp, is_streaming, sequence_number, created_at)
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
         FROM local_llm_conversation_messages WHERE id = ?1",
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
         FROM local_llm_conversation_messages WHERE session_id = ?1 ORDER BY sequence_number ASC",
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
        "SELECT MAX(sequence_number) FROM local_llm_conversation_messages WHERE session_id = ?1",
        params![session_id],
        |row| row.get(0),
    )?;
    Ok(max.unwrap_or(0) + 1)
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
         FROM local_llm_conversation_secrets WHERE session_id = ?1",
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
        "INSERT INTO local_llm_conversation_secrets (session_id, encrypted_secret, nonce, created_at)
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
        "DELETE FROM local_llm_conversation_secrets WHERE session_id = ?1",
        params![session_id],
    )?;
    Ok(count > 0)
}

/// Check if a session secret exists.
pub fn has_session_secret(conn: &Connection, session_id: &str) -> DatabaseResult<bool> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM local_llm_conversation_secrets WHERE session_id = ?1",
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
                machine_id: None,
                space_id: None,
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
                machine_id: None,
                space_id: None,
                title: "Test Session".to_string(),
                agent_name: None,
                issue_id: None,
                issue_title: None,
                issue_url: None,
                provider: None,
                provider_session_id: None,
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
                machine_id: None,
                space_id: None,
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
                machine_id: None,
                space_id: None,
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
                machine_id: None,
                space_id: None,
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
        let issue_id = "issue-123".to_string();

        let session = insert_session(
            &conn,
            &NewAgentCodingSession {
                id: "s1".into(),
                repository_id: repo_id,
                machine_id: None,
                space_id: None,
                title: "My Session".into(),
                agent_name: Some("Debug Agent".into()),
                issue_id: Some(issue_id.clone()),
                issue_title: Some("Fix launch bug".into()),
                issue_url: Some("https://example.com/issues/ENG-123".into()),
                provider: Some("claude".into()),
                provider_session_id: Some("claude-xyz".into()),
                claude_session_id: Some("claude-xyz".into()),
                is_worktree: true,
                worktree_path: Some("/worktree".into()),
            },
        )
        .unwrap();

        assert_eq!(session.id, "s1");
        assert_eq!(session.title, "My Session");
        assert_eq!(session.agent_name, Some("Debug Agent".into()));
        assert_eq!(session.issue_id, Some(issue_id));
        assert_eq!(session.issue_title, Some("Fix launch bug".into()));
        assert_eq!(
            session.issue_url,
            Some("https://example.com/issues/ENG-123".into())
        );
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
                machine_id: None,
                space_id: None,
                title: "First".into(),
                agent_name: None,
                issue_id: None,
                issue_title: None,
                issue_url: None,
                provider: None,
                provider_session_id: None,
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
                machine_id: None,
                space_id: None,
                title: "Second".into(),
                agent_name: Some("Debug Agent".into()),
                issue_id: Some("issue-999".into()),
                issue_title: Some("Investigate session linking".into()),
                issue_url: Some("https://example.com/issues/ENG-999".into()),
                provider: None,
                provider_session_id: None,
                claude_session_id: None,
                is_worktree: false,
                worktree_path: None,
            },
        )
        .unwrap();

        let sessions = list_sessions_for_repository(&conn, &repo_id).unwrap();
        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].issue_id.as_deref(), Some("issue-999"));
        assert_eq!(
            sessions[0].issue_url.as_deref(),
            Some("https://example.com/issues/ENG-999")
        );

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
