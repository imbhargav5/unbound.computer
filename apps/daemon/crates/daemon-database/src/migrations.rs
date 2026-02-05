//! Database migrations.
//!
//! This module contains all SQL migrations for the database schema.
//! Migrations are run in order and tracked in the `migrations` table.

use crate::DatabaseResult;
use rusqlite::Connection;
use tracing::{debug, info};

/// Current schema version.
pub const CURRENT_VERSION: i32 = 10;

/// Run all pending migrations.
pub fn run_migrations(conn: &Connection) -> DatabaseResult<()> {
    // Create migrations tracking table
    conn.execute(
        "CREATE TABLE IF NOT EXISTS migrations (
            version INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            applied_at TEXT NOT NULL DEFAULT (datetime('now'))
        )",
        [],
    )?;

    let current_version: i32 = conn
        .query_row(
            "SELECT COALESCE(MAX(version), 0) FROM migrations",
            [],
            |row| row.get(0),
        )
        .unwrap_or(0);

    info!(current_version, target_version = CURRENT_VERSION, "Running migrations");

    if current_version < 1 {
        migrate_v1_initial_schema(conn)?;
    }
    if current_version < 2 {
        migrate_v2_outbox(conn)?;
    }
    if current_version < 3 {
        migrate_v3_normalize_tables(conn)?;
    }
    if current_version < 4 {
        migrate_v4_events_table(conn)?;
    }
    if current_version < 5 {
        migrate_v5_session_secrets(conn)?;
    }
    if current_version < 6 {
        migrate_v6_drop_events_table(conn)?;
    }
    if current_version < 7 {
        migrate_v7_drop_role_column(conn)?;
    }
    if current_version < 8 {
        migrate_v8_plaintext_messages(conn)?;
    }
    if current_version < 9 {
        migrate_v9_supabase_message_outbox(conn)?;
    }
    if current_version < 10 {
        migrate_v10_supabase_sync_state(conn)?;
    }

    info!("Migrations complete");
    Ok(())
}

fn record_migration(conn: &Connection, version: i32, name: &str) -> DatabaseResult<()> {
    conn.execute(
        "INSERT INTO migrations (version, name) VALUES (?1, ?2)",
        rusqlite::params![version, name],
    )?;
    debug!(version, name, "Migration applied");
    Ok(())
}

/// V1: Initial schema - repositories, sessions, messages, settings.
fn migrate_v1_initial_schema(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v1: initial schema");

    // repositories table
    conn.execute_batch(
        "
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
        ",
    )?;

    // agent_coding_sessions table
    conn.execute_batch(
        "
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
        ",
    )?;

    // agent_coding_session_state table
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS agent_coding_session_state (
            session_id TEXT PRIMARY KEY REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            agent_status TEXT NOT NULL DEFAULT 'idle',
            queued_commands TEXT,
            diff_summary TEXT,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ",
    )?;

    // agent_coding_session_messages table
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS agent_coding_session_messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            role TEXT NOT NULL,
            content_encrypted BLOB NOT NULL,
            content_nonce BLOB NOT NULL,
            timestamp TEXT NOT NULL DEFAULT (datetime('now')),
            is_streaming INTEGER NOT NULL DEFAULT 0,
            sequence_number INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            debugging_decrypted_payload TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_messages_session_id
            ON agent_coding_session_messages(session_id);
        CREATE INDEX IF NOT EXISTS idx_messages_session_seq
            ON agent_coding_session_messages(session_id, sequence_number);
        CREATE INDEX IF NOT EXISTS idx_messages_timestamp
            ON agent_coding_session_messages(timestamp);
        ",
    )?;

    // user_settings table
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS user_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            value_type TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ",
    )?;

    record_migration(conn, 1, "initial_schema")?;
    Ok(())
}

/// V2: Event outbox for relay delivery.
fn migrate_v2_outbox(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v2: event outbox");

    conn.execute_batch(
        "
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

        -- Cleanup trigger for acknowledged events older than 24 hours
        CREATE TRIGGER IF NOT EXISTS cleanup_acked_events
        AFTER INSERT ON agent_coding_session_event_outbox
        BEGIN
            DELETE FROM agent_coding_session_event_outbox
            WHERE status = 'acked' AND acked_at < datetime('now', '-1 day');
        END;
        ",
    )?;

    record_migration(conn, 2, "event_outbox")?;
    Ok(())
}

/// V3: Normalize table names (compatibility with macOS app).
fn migrate_v3_normalize_tables(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v3: normalize tables");

    // Image uploads table
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS agent_coding_session_image_uploads (
            id TEXT PRIMARY KEY,
            message_id TEXT REFERENCES agent_coding_session_messages(id) ON DELETE SET NULL,
            session_id TEXT NOT NULL REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            filename TEXT NOT NULL,
            stored_filename TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            width INTEGER,
            height INTEGER,
            checksum TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE INDEX IF NOT EXISTS idx_image_uploads_session_id
            ON agent_coding_session_image_uploads(session_id);
        CREATE INDEX IF NOT EXISTS idx_image_uploads_message_id
            ON agent_coding_session_image_uploads(message_id);
        ",
    )?;

    // Attachments table
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS agent_coding_session_attachments (
            id TEXT PRIMARY KEY,
            message_id TEXT REFERENCES agent_coding_session_messages(id) ON DELETE SET NULL,
            session_id TEXT NOT NULL REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            filename TEXT NOT NULL,
            stored_filename TEXT NOT NULL,
            file_type TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            checksum TEXT,
            metadata_json TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE INDEX IF NOT EXISTS idx_attachments_session_id
            ON agent_coding_session_attachments(session_id);
        CREATE INDEX IF NOT EXISTS idx_attachments_message_id
            ON agent_coding_session_attachments(message_id);
        CREATE INDEX IF NOT EXISTS idx_attachments_file_type
            ON agent_coding_session_attachments(file_type);
        ",
    )?;

    record_migration(conn, 3, "normalize_tables")?;
    Ok(())
}

/// V4: Raw Claude events table.
fn migrate_v4_events_table(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v4: events table");

    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS agent_coding_session_events (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            sequence_number INTEGER NOT NULL,
            content_encrypted BLOB NOT NULL,
            content_nonce BLOB NOT NULL,
            timestamp TEXT NOT NULL DEFAULT (datetime('now')),
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            debugging_raw_json TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_events_session_seq
            ON agent_coding_session_events(session_id, sequence_number);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_events_session_seq_unique
            ON agent_coding_session_events(session_id, sequence_number);
        ",
    )?;

    record_migration(conn, 4, "events_table")?;
    Ok(())
}

/// V5: Session secrets table (encrypted with device key, stored locally).
fn migrate_v5_session_secrets(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v5: session secrets table");

    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS session_secrets (
            session_id TEXT PRIMARY KEY REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            encrypted_secret BLOB NOT NULL,
            nonce BLOB NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        ",
    )?;

    record_migration(conn, 5, "session_secrets")?;
    Ok(())
}

/// V6: Drop events table (outbox already tracks relay acks via message_id).
fn migrate_v6_drop_events_table(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v6: drop events table");

    conn.execute_batch(
        "
        DROP TABLE IF EXISTS agent_coding_session_events;
        ",
    )?;

    record_migration(conn, 6, "drop_events_table")?;
    Ok(())
}

/// V7: Drop role column from messages table.
/// The role is already embedded in the encrypted JSON payload, so it's redundant.
/// SQLite doesn't support DROP COLUMN directly, so we need to recreate the table.
fn migrate_v7_drop_role_column(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v7: drop role column from messages");

    conn.execute_batch(
        "
        -- Create new table without role column
        CREATE TABLE agent_coding_session_messages_new (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            content_encrypted BLOB NOT NULL,
            content_nonce BLOB NOT NULL,
            timestamp TEXT NOT NULL DEFAULT (datetime('now')),
            is_streaming INTEGER NOT NULL DEFAULT 0,
            sequence_number INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            debugging_decrypted_payload TEXT
        );

        -- Copy data from old table (excluding role)
        INSERT INTO agent_coding_session_messages_new
            (id, session_id, content_encrypted, content_nonce, timestamp, is_streaming, sequence_number, created_at, debugging_decrypted_payload)
        SELECT id, session_id, content_encrypted, content_nonce, timestamp, is_streaming, sequence_number, created_at, debugging_decrypted_payload
        FROM agent_coding_session_messages;

        -- Drop old table
        DROP TABLE agent_coding_session_messages;

        -- Rename new table
        ALTER TABLE agent_coding_session_messages_new RENAME TO agent_coding_session_messages;

        -- Recreate indexes
        CREATE INDEX IF NOT EXISTS idx_messages_session_id
            ON agent_coding_session_messages(session_id);
        CREATE INDEX IF NOT EXISTS idx_messages_session_seq
            ON agent_coding_session_messages(session_id, sequence_number);
        CREATE INDEX IF NOT EXISTS idx_messages_timestamp
            ON agent_coding_session_messages(timestamp);
        ",
    )?;

    record_migration(conn, 7, "drop_role_column")?;
    Ok(())
}

/// V8: Convert messages to plaintext storage.
/// Remove encryption columns (content_encrypted, content_nonce, debugging_decrypted_payload)
/// and add a simple content TEXT column.
fn migrate_v8_plaintext_messages(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v8: plaintext messages");

    conn.execute_batch(
        "
        -- Create new table with plaintext content column
        CREATE TABLE agent_coding_session_messages_new (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            content TEXT NOT NULL,
            timestamp TEXT NOT NULL DEFAULT (datetime('now')),
            is_streaming INTEGER NOT NULL DEFAULT 0,
            sequence_number INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        -- Copy data from old table, using debugging_decrypted_payload as content
        -- For messages without debugging payload, we use empty string (data is lost)
        INSERT INTO agent_coding_session_messages_new
            (id, session_id, content, timestamp, is_streaming, sequence_number, created_at)
        SELECT id, session_id, COALESCE(debugging_decrypted_payload, ''), timestamp, is_streaming, sequence_number, created_at
        FROM agent_coding_session_messages;

        -- Drop old table
        DROP TABLE agent_coding_session_messages;

        -- Rename new table
        ALTER TABLE agent_coding_session_messages_new RENAME TO agent_coding_session_messages;

        -- Recreate indexes
        CREATE INDEX IF NOT EXISTS idx_messages_session_id
            ON agent_coding_session_messages(session_id);
        CREATE INDEX IF NOT EXISTS idx_messages_session_seq
            ON agent_coding_session_messages(session_id, sequence_number);
        CREATE INDEX IF NOT EXISTS idx_messages_timestamp
            ON agent_coding_session_messages(timestamp);
        ",
    )?;

    record_migration(conn, 8, "plaintext_messages")?;
    Ok(())
}

/// V9: Supabase message outbox table.
fn migrate_v9_supabase_message_outbox(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v9: supabase_message_outbox");

    conn.execute_batch(
        "
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
        ",
    )?;

    record_migration(conn, 9, "supabase_message_outbox")?;
    Ok(())
}

/// V10: Supabase sync state table (cursor-based sync per session).
/// Replaces per-message outbox with per-session sync tracking.
fn migrate_v10_supabase_sync_state(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v10: supabase_sync_state");

    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS agent_coding_session_supabase_sync_state (
            session_id TEXT PRIMARY KEY REFERENCES agent_coding_sessions(id) ON DELETE CASCADE,
            last_synced_sequence_number INTEGER NOT NULL DEFAULT 0,
            last_sync_at TEXT,
            last_error TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_attempt_at TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_supabase_sync_state_last_attempt_at
            ON agent_coding_session_supabase_sync_state(last_attempt_at);
        ",
    )?;

    record_migration(conn, 10, "supabase_sync_state")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_migrations_run_successfully() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        // Verify tables exist
        let tables: Vec<String> = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            .unwrap()
            .query_map([], |row| row.get(0))
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();

        assert!(tables.contains(&"repositories".to_string()));
        assert!(tables.contains(&"agent_coding_sessions".to_string()));
        assert!(tables.contains(&"agent_coding_session_messages".to_string()));
        assert!(tables.contains(&"agent_coding_session_event_outbox".to_string()));
        assert!(tables.contains(&"agent_coding_session_message_supabase_outbox".to_string()));
        assert!(tables.contains(&"user_settings".to_string()));
        assert!(tables.contains(&"session_secrets".to_string()));
        assert!(tables.contains(&"migrations".to_string()));
    }

    #[test]
    fn test_migrations_are_idempotent() {
        let conn = Connection::open_in_memory().unwrap();

        // Run migrations twice
        run_migrations(&conn).unwrap();
        run_migrations(&conn).unwrap();

        // Should not error
        let version: i32 = conn
            .query_row("SELECT MAX(version) FROM migrations", [], |row| row.get(0))
            .unwrap();

        assert_eq!(version, 10);
    }

    #[test]
    fn test_messages_table_plaintext_content() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        // Verify the table has plaintext content column
        let columns: Vec<String> = conn
            .prepare("PRAGMA table_info(agent_coding_session_messages)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1)) // Column 1 is name
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();

        // Should have content column
        assert!(columns.contains(&"content".to_string()), "content column should exist");
        // Should NOT have encryption columns
        assert!(!columns.contains(&"role".to_string()), "role column should not exist");
        assert!(!columns.contains(&"content_encrypted".to_string()), "content_encrypted should not exist");
        assert!(!columns.contains(&"content_nonce".to_string()), "content_nonce should not exist");
        assert!(!columns.contains(&"debugging_decrypted_payload".to_string()), "debugging_decrypted_payload should not exist");
    }
}
