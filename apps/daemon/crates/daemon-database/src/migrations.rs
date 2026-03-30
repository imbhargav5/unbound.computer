//! Database migrations.
//!
//! This module contains all SQL migrations for the database schema.
//! Migrations are run in order and tracked in the `migrations` table.

use crate::DatabaseResult;
use rusqlite::{Connection, OptionalExtension};
use std::collections::HashSet;
use tracing::{debug, info};

/// Current schema version.
pub const CURRENT_VERSION: i32 = 27;

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

    info!(
        current_version,
        target_version = CURRENT_VERSION,
        "Running migrations"
    );

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
        migrate_v9_retired_cloud_outbox(conn)?;
    }
    if current_version < 10 {
        migrate_v10_retired_cloud_sync_state(conn)?;
    }
    if current_version < 11 {
        migrate_v11_session_state_runtime_envelope(conn)?;
    }
    if current_version < 12 {
        migrate_v12_board_schema(conn)?;
    }
    if current_version < 13 {
        migrate_v13_session_agent_metadata(conn)?;
    }
    if current_version < 14 {
        migrate_v14_session_issue_metadata(conn)?;
    }
    if current_version < 15 {
        migrate_v15_reconcile_board_and_session_metadata(conn)?;
    }
    if current_version < 16 {
        migrate_v16_agent_runs_rename(conn)?;
    }
    if current_version < 17 {
        migrate_v17_issue_linked_runs_and_comment_targets(conn)?;
    }
    if current_version < 18 {
        migrate_v18_session_provider_metadata(conn)?;
    }
    if current_version < 19 {
        migrate_v19_prune_unused_board_schema(conn)?;
    }
    if current_version < 20 {
        migrate_v20_rename_local_llm_conversation_tables(conn)?;
    }
    if current_version < 21 {
        migrate_v21_rename_issue_tables_to_tasks(conn)?;
    }
    if current_version < 22 {
        migrate_v22_rename_project_tables_to_repositories_and_worktrees(conn)?;
    }
    if current_version < 23 {
        migrate_v23_rebuild_foreign_keys_after_table_renames(conn)?;
    }
    if current_version < 24 {
        migrate_v24_machine_space_hierarchy(conn)?;
    }
    if current_version < 25 {
        migrate_v25_spaces_add_user_id(conn)?;
    }
    if current_version < 26 {
        migrate_v26_drop_agent_and_run_tables(conn)?;
    }
    if current_version < 27 {
        migrate_v27_drop_board_tables(conn)?;
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
            provider TEXT,
            provider_session_id TEXT,
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

/// V9: Retired cloud outbox migration.
fn migrate_v9_retired_cloud_outbox(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v9: retired cloud outbox");
    record_migration(conn, 9, "retired_cloud_outbox")?;
    Ok(())
}

/// V10: Retired cloud sync state migration.
fn migrate_v10_retired_cloud_sync_state(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v10: retired cloud sync state");
    record_migration(conn, 10, "retired_cloud_sync_state")?;
    Ok(())
}

/// V11: Move session state to a grouped runtime envelope JSON blob.
fn migrate_v11_session_state_runtime_envelope(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v11: session_state_runtime_envelope");

    let mut stmt = conn.prepare("PRAGMA table_info(agent_coding_session_state)")?;
    let columns: HashSet<String> = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .collect();

    let has_state_json = columns.contains("state_json");
    let has_updated_at_ms = columns.contains("updated_at_ms");
    let has_agent_status = columns.contains("agent_status");

    // Already in target format.
    if has_state_json && has_updated_at_ms && !has_agent_status {
        record_migration(conn, 11, "session_state_runtime_envelope")?;
        return Ok(());
    }

    conn.execute_batch(
        "
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
        ",
    )?;

    if columns.contains("session_id") {
        if has_agent_status {
            conn.execute_batch(
                "
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
                ",
            )?;
        } else if has_state_json {
            conn.execute_batch(
                "
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
                ",
            )?;
        }
    }

    conn.execute_batch(
        "
        DROP TABLE IF EXISTS agent_coding_session_state;
        ALTER TABLE agent_coding_session_state_new RENAME TO agent_coding_session_state;
        ",
    )?;

    record_migration(conn, 11, "session_state_runtime_envelope")?;
    Ok(())
}

fn column_names(conn: &Connection, table_name: &str) -> DatabaseResult<HashSet<String>> {
    let sql = format!("PRAGMA table_info({table_name})");
    let mut stmt = conn.prepare(&sql)?;
    let columns = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .collect();
    Ok(columns)
}

fn table_exists(conn: &Connection, table_name: &str) -> DatabaseResult<bool> {
    let exists = conn
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1 LIMIT 1",
            [table_name],
            |row| row.get::<_, i64>(0),
        )
        .optional()?;
    Ok(exists.is_some())
}

const SESSION_TABLE_LEGACY: &str = "agent_coding_sessions";
const SESSION_TABLE_RENAMED: &str = "local_llm_conversations";

fn session_table_name(conn: &Connection) -> DatabaseResult<&'static str> {
    if table_exists(conn, SESSION_TABLE_RENAMED)? {
        return Ok(SESSION_TABLE_RENAMED);
    }
    Ok(SESSION_TABLE_LEGACY)
}

fn add_column_if_missing(
    conn: &Connection,
    table_name: &str,
    column_name: &str,
    column_sql: &str,
) -> DatabaseResult<()> {
    if !column_names(conn, table_name)?.contains(column_name) {
        conn.execute_batch(&format!(
            "ALTER TABLE {table_name} ADD COLUMN {column_sql};"
        ))?;
    }
    Ok(())
}

fn ensure_board_schema(conn: &Connection) -> DatabaseResult<()> {
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS companies (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            issue_prefix TEXT NOT NULL DEFAULT 'UNB',
            issue_counter INTEGER NOT NULL DEFAULT 0,
            budget_monthly_cents INTEGER NOT NULL DEFAULT 0,
            spent_monthly_cents INTEGER NOT NULL DEFAULT 0,
            require_board_approval_for_new_agents INTEGER NOT NULL DEFAULT 1,
            brand_color TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS companies_issue_prefix_idx
            ON companies(issue_prefix);

        CREATE TABLE IF NOT EXISTS auth_users (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            email_verified INTEGER NOT NULL DEFAULT 0,
            image TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS auth_users_email_idx
            ON auth_users(email);

        CREATE TABLE IF NOT EXISTS auth_sessions (
            id TEXT PRIMARY KEY,
            expires_at TEXT NOT NULL,
            token TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            ip_address TEXT,
            user_agent TEXT,
            user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE
        );
        CREATE UNIQUE INDEX IF NOT EXISTS auth_sessions_token_idx
            ON auth_sessions(token);
        CREATE INDEX IF NOT EXISTS auth_sessions_user_idx
            ON auth_sessions(user_id);

        CREATE TABLE IF NOT EXISTS auth_accounts (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
            access_token TEXT,
            refresh_token TEXT,
            id_token TEXT,
            access_token_expires_at TEXT,
            refresh_token_expires_at TEXT,
            scope TEXT,
            password TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS auth_accounts_user_idx
            ON auth_accounts(user_id);
        CREATE INDEX IF NOT EXISTS auth_accounts_provider_idx
            ON auth_accounts(provider_id, account_id);

        CREATE TABLE IF NOT EXISTS auth_verifications (
            id TEXT PRIMARY KEY,
            identifier TEXT NOT NULL,
            value TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            created_at TEXT,
            updated_at TEXT
        );
        CREATE INDEX IF NOT EXISTS auth_verifications_identifier_idx
            ON auth_verifications(identifier);

        CREATE TABLE IF NOT EXISTS instance_user_roles (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
            role TEXT NOT NULL DEFAULT 'instance_admin',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS instance_user_roles_user_role_unique_idx
            ON instance_user_roles(user_id, role);
        CREATE INDEX IF NOT EXISTS instance_user_roles_role_idx
            ON instance_user_roles(role);

        CREATE TABLE IF NOT EXISTS agents (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            slug TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'general',
            title TEXT,
            icon TEXT,
            status TEXT NOT NULL DEFAULT 'idle',
            reports_to TEXT REFERENCES agents(id) ON DELETE SET NULL,
            capabilities TEXT,
            adapter_type TEXT NOT NULL DEFAULT 'process',
            adapter_config TEXT NOT NULL DEFAULT '{}',
            runtime_config TEXT NOT NULL DEFAULT '{}',
            budget_monthly_cents INTEGER NOT NULL DEFAULT 0,
            spent_monthly_cents INTEGER NOT NULL DEFAULT 0,
            permissions TEXT NOT NULL DEFAULT '{}',
            last_heartbeat_at TEXT,
            metadata TEXT,
            home_path TEXT,
            instructions_path TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (json_valid(adapter_config)),
            CHECK (json_valid(runtime_config)),
            CHECK (json_valid(permissions)),
            CHECK (metadata IS NULL OR json_valid(metadata))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS agents_company_slug_idx
            ON agents(company_id, slug);
        CREATE INDEX IF NOT EXISTS agents_company_status_idx
            ON agents(company_id, status);
        CREATE INDEX IF NOT EXISTS agents_company_reports_to_idx
            ON agents(company_id, reports_to);

        CREATE TABLE IF NOT EXISTS company_memberships (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            principal_type TEXT NOT NULL,
            principal_id TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'active',
            membership_role TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS company_memberships_company_principal_unique_idx
            ON company_memberships(company_id, principal_type, principal_id);
        CREATE INDEX IF NOT EXISTS company_memberships_principal_status_idx
            ON company_memberships(principal_type, principal_id, status);
        CREATE INDEX IF NOT EXISTS company_memberships_company_status_idx
            ON company_memberships(company_id, status);

        CREATE TABLE IF NOT EXISTS principal_permission_grants (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            principal_type TEXT NOT NULL,
            principal_id TEXT NOT NULL,
            permission_key TEXT NOT NULL,
            scope TEXT,
            granted_by_user_id TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (scope IS NULL OR json_valid(scope))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS principal_permission_grants_unique_idx
            ON principal_permission_grants(company_id, principal_type, principal_id, permission_key);
        CREATE INDEX IF NOT EXISTS principal_permission_grants_company_permission_idx
            ON principal_permission_grants(company_id, permission_key);

        CREATE TABLE IF NOT EXISTS invites (
            id TEXT PRIMARY KEY,
            company_id TEXT REFERENCES companies(id) ON DELETE CASCADE,
            invite_type TEXT NOT NULL DEFAULT 'company_join',
            token_hash TEXT NOT NULL,
            allowed_join_types TEXT NOT NULL DEFAULT 'both',
            defaults_payload TEXT,
            expires_at TEXT NOT NULL,
            invited_by_user_id TEXT,
            revoked_at TEXT,
            accepted_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (defaults_payload IS NULL OR json_valid(defaults_payload))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS invites_token_hash_unique_idx
            ON invites(token_hash);
        CREATE INDEX IF NOT EXISTS invites_company_invite_state_idx
            ON invites(company_id, invite_type, revoked_at, expires_at);

        CREATE TABLE IF NOT EXISTS join_requests (
            id TEXT PRIMARY KEY,
            invite_id TEXT NOT NULL REFERENCES invites(id) ON DELETE CASCADE,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            request_type TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending_approval',
            request_ip TEXT NOT NULL,
            requesting_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            request_email_snapshot TEXT,
            agent_name TEXT,
            adapter_type TEXT,
            capabilities TEXT,
            agent_defaults_payload TEXT,
            claim_secret_hash TEXT,
            claim_secret_expires_at TEXT,
            claim_secret_consumed_at TEXT,
            created_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            approved_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            approved_at TEXT,
            rejected_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            rejected_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (agent_defaults_payload IS NULL OR json_valid(agent_defaults_payload))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS join_requests_invite_unique_idx
            ON join_requests(invite_id);
        CREATE INDEX IF NOT EXISTS join_requests_company_status_type_created_idx
            ON join_requests(company_id, status, request_type, created_at);

        CREATE TABLE IF NOT EXISTS agent_config_revisions (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            created_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            created_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            source TEXT NOT NULL DEFAULT 'patch',
            rolled_back_from_revision_id TEXT,
            changed_keys TEXT NOT NULL DEFAULT '[]',
            before_config TEXT NOT NULL,
            after_config TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (json_valid(changed_keys)),
            CHECK (json_valid(before_config)),
            CHECK (json_valid(after_config))
        );
        CREATE INDEX IF NOT EXISTS agent_config_revisions_company_agent_created_idx
            ON agent_config_revisions(company_id, agent_id, created_at);
        CREATE INDEX IF NOT EXISTS agent_config_revisions_agent_created_idx
            ON agent_config_revisions(agent_id, created_at);

        CREATE TABLE IF NOT EXISTS agent_api_keys (
            id TEXT PRIMARY KEY,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            key_hash TEXT NOT NULL,
            last_used_at TEXT,
            revoked_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS agent_api_keys_key_hash_idx
            ON agent_api_keys(key_hash);
        CREATE INDEX IF NOT EXISTS agent_api_keys_company_agent_idx
            ON agent_api_keys(company_id, agent_id);

        CREATE TABLE IF NOT EXISTS agent_runtime_state (
            agent_id TEXT PRIMARY KEY REFERENCES agents(id) ON DELETE CASCADE,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            adapter_type TEXT NOT NULL,
            session_id TEXT,
            state_json TEXT NOT NULL DEFAULT '{}',
            last_run_id TEXT,
            last_run_status TEXT,
            total_input_tokens INTEGER NOT NULL DEFAULT 0,
            total_output_tokens INTEGER NOT NULL DEFAULT 0,
            total_cached_input_tokens INTEGER NOT NULL DEFAULT 0,
            total_cost_cents INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (json_valid(state_json))
        );
        CREATE INDEX IF NOT EXISTS agent_runtime_state_company_agent_idx
            ON agent_runtime_state(company_id, agent_id);
        CREATE INDEX IF NOT EXISTS agent_runtime_state_company_updated_idx
            ON agent_runtime_state(company_id, updated_at);

        CREATE TABLE IF NOT EXISTS agent_task_sessions (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            adapter_type TEXT NOT NULL,
            task_key TEXT NOT NULL,
            session_params_json TEXT,
            session_display_id TEXT,
            last_run_id TEXT,
            last_error TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (session_params_json IS NULL OR json_valid(session_params_json))
        );
        CREATE UNIQUE INDEX IF NOT EXISTS agent_task_sessions_company_agent_adapter_task_uniq
            ON agent_task_sessions(company_id, agent_id, adapter_type, task_key);
        CREATE INDEX IF NOT EXISTS agent_task_sessions_company_agent_updated_idx
            ON agent_task_sessions(company_id, agent_id, updated_at);
        CREATE INDEX IF NOT EXISTS agent_task_sessions_company_task_updated_idx
            ON agent_task_sessions(company_id, task_key, updated_at);

        CREATE TABLE IF NOT EXISTS agent_wakeup_requests (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            source TEXT NOT NULL,
            trigger_detail TEXT,
            reason TEXT,
            payload TEXT,
            status TEXT NOT NULL DEFAULT 'queued',
            coalesced_count INTEGER NOT NULL DEFAULT 0,
            requested_by_actor_type TEXT,
            requested_by_actor_id TEXT,
            idempotency_key TEXT,
            run_id TEXT,
            requested_at TEXT NOT NULL DEFAULT (datetime('now')),
            claimed_at TEXT,
            finished_at TEXT,
            error TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (payload IS NULL OR json_valid(payload))
        );
        CREATE INDEX IF NOT EXISTS agent_wakeup_requests_company_agent_status_idx
            ON agent_wakeup_requests(company_id, agent_id, status);
        CREATE INDEX IF NOT EXISTS agent_wakeup_requests_company_requested_idx
            ON agent_wakeup_requests(company_id, requested_at);
        CREATE INDEX IF NOT EXISTS agent_wakeup_requests_agent_requested_idx
            ON agent_wakeup_requests(agent_id, requested_at);

        CREATE TABLE IF NOT EXISTS goals (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            description TEXT,
            level TEXT NOT NULL DEFAULT 'task',
            status TEXT NOT NULL DEFAULT 'planned',
            parent_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
            owner_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS goals_company_idx
            ON goals(company_id);

        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
            name TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'backlog',
            lead_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            target_date TEXT,
            color TEXT,
            execution_workspace_policy TEXT,
            archived_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (execution_workspace_policy IS NULL OR json_valid(execution_workspace_policy))
        );
        CREATE INDEX IF NOT EXISTS projects_company_idx
            ON projects(company_id);

        CREATE TABLE IF NOT EXISTS project_workspaces (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            cwd TEXT,
            repo_url TEXT,
            repo_ref TEXT,
            metadata TEXT,
            is_primary INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (metadata IS NULL OR json_valid(metadata))
        );
        CREATE INDEX IF NOT EXISTS project_workspaces_company_project_idx
            ON project_workspaces(company_id, project_id);
        CREATE INDEX IF NOT EXISTS project_workspaces_project_primary_idx
            ON project_workspaces(project_id, is_primary);

        CREATE TABLE IF NOT EXISTS project_goals (
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (project_id, goal_id)
        );
        CREATE INDEX IF NOT EXISTS project_goals_project_idx
            ON project_goals(project_id);
        CREATE INDEX IF NOT EXISTS project_goals_goal_idx
            ON project_goals(goal_id);
        CREATE INDEX IF NOT EXISTS project_goals_company_idx
            ON project_goals(company_id);

        CREATE TABLE IF NOT EXISTS heartbeat_runs (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            invocation_source TEXT NOT NULL DEFAULT 'on_demand',
            trigger_detail TEXT,
            status TEXT NOT NULL DEFAULT 'queued',
            started_at TEXT,
            finished_at TEXT,
            error TEXT,
            wakeup_request_id TEXT REFERENCES agent_wakeup_requests(id) ON DELETE SET NULL,
            exit_code INTEGER,
            signal TEXT,
            usage_json TEXT,
            result_json TEXT,
            session_id_before TEXT,
            session_id_after TEXT,
            log_store TEXT,
            log_ref TEXT,
            log_bytes INTEGER,
            log_sha256 TEXT,
            log_compressed INTEGER NOT NULL DEFAULT 0,
            stdout_excerpt TEXT,
            stderr_excerpt TEXT,
            error_code TEXT,
            external_run_id TEXT,
            context_snapshot TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (usage_json IS NULL OR json_valid(usage_json)),
            CHECK (result_json IS NULL OR json_valid(result_json)),
            CHECK (context_snapshot IS NULL OR json_valid(context_snapshot))
        );
        CREATE INDEX IF NOT EXISTS heartbeat_runs_company_agent_started_idx
            ON heartbeat_runs(company_id, agent_id, started_at);

        CREATE TABLE IF NOT EXISTS issues (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
            goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
            parent_id TEXT REFERENCES issues(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'backlog',
            priority TEXT NOT NULL DEFAULT 'medium',
            assignee_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            assignee_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            checkout_run_id TEXT REFERENCES heartbeat_runs(id) ON DELETE SET NULL,
            execution_run_id TEXT REFERENCES heartbeat_runs(id) ON DELETE SET NULL,
            execution_agent_name_key TEXT,
            execution_locked_at TEXT,
            created_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            created_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            issue_number INTEGER,
            identifier TEXT,
            request_depth INTEGER NOT NULL DEFAULT 0,
            billing_code TEXT,
            assignee_adapter_overrides TEXT,
            execution_workspace_settings TEXT,
            started_at TEXT,
            completed_at TEXT,
            cancelled_at TEXT,
            hidden_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (assignee_adapter_overrides IS NULL OR json_valid(assignee_adapter_overrides)),
            CHECK (execution_workspace_settings IS NULL OR json_valid(execution_workspace_settings))
        );
        CREATE INDEX IF NOT EXISTS issues_company_status_idx
            ON issues(company_id, status);
        CREATE INDEX IF NOT EXISTS issues_company_assignee_status_idx
            ON issues(company_id, assignee_agent_id, status);
        CREATE INDEX IF NOT EXISTS issues_company_assignee_user_status_idx
            ON issues(company_id, assignee_user_id, status);
        CREATE INDEX IF NOT EXISTS issues_company_parent_idx
            ON issues(company_id, parent_id);
        CREATE INDEX IF NOT EXISTS issues_company_project_idx
            ON issues(company_id, project_id);
        CREATE UNIQUE INDEX IF NOT EXISTS issues_identifier_idx
            ON issues(identifier);

        CREATE TABLE IF NOT EXISTS labels (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS labels_company_idx
            ON labels(company_id);
        CREATE UNIQUE INDEX IF NOT EXISTS labels_company_name_idx
            ON labels(company_id, name);

        CREATE TABLE IF NOT EXISTS issue_labels (
            issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
            label_id TEXT NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (issue_id, label_id)
        );
        CREATE INDEX IF NOT EXISTS issue_labels_issue_idx
            ON issue_labels(issue_id);
        CREATE INDEX IF NOT EXISTS issue_labels_label_idx
            ON issue_labels(label_id);
        CREATE INDEX IF NOT EXISTS issue_labels_company_idx
            ON issue_labels(company_id);

        CREATE TABLE IF NOT EXISTS approvals (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            type TEXT NOT NULL,
            requested_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            requested_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            payload TEXT NOT NULL,
            decision_note TEXT,
            decided_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            decided_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (json_valid(payload))
        );
        CREATE INDEX IF NOT EXISTS approvals_company_status_type_idx
            ON approvals(company_id, status, type);

        CREATE TABLE IF NOT EXISTS issue_approvals (
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
            approval_id TEXT NOT NULL REFERENCES approvals(id) ON DELETE CASCADE,
            linked_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            linked_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (issue_id, approval_id)
        );
        CREATE INDEX IF NOT EXISTS issue_approvals_issue_idx
            ON issue_approvals(issue_id);
        CREATE INDEX IF NOT EXISTS issue_approvals_approval_idx
            ON issue_approvals(approval_id);
        CREATE INDEX IF NOT EXISTS issue_approvals_company_idx
            ON issue_approvals(company_id);

        CREATE TABLE IF NOT EXISTS issue_comments (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
            author_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            author_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            body TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS issue_comments_issue_idx
            ON issue_comments(issue_id);
        CREATE INDEX IF NOT EXISTS issue_comments_company_idx
            ON issue_comments(company_id);
        CREATE INDEX IF NOT EXISTS issue_comments_company_issue_created_at_idx
            ON issue_comments(company_id, issue_id, created_at);
        CREATE INDEX IF NOT EXISTS issue_comments_company_author_issue_created_at_idx
            ON issue_comments(company_id, author_user_id, issue_id, created_at);

        CREATE TABLE IF NOT EXISTS issue_read_states (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
            user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
            last_read_at TEXT NOT NULL DEFAULT (datetime('now')),
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS issue_read_states_company_issue_idx
            ON issue_read_states(company_id, issue_id);
        CREATE INDEX IF NOT EXISTS issue_read_states_company_user_idx
            ON issue_read_states(company_id, user_id);
        CREATE UNIQUE INDEX IF NOT EXISTS issue_read_states_company_issue_user_idx
            ON issue_read_states(company_id, issue_id, user_id);

        CREATE TABLE IF NOT EXISTS assets (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            provider TEXT NOT NULL,
            object_key TEXT NOT NULL,
            content_type TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            original_filename TEXT,
            created_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            created_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS assets_company_created_idx
            ON assets(company_id, created_at);
        CREATE INDEX IF NOT EXISTS assets_company_provider_idx
            ON assets(company_id, provider);
        CREATE UNIQUE INDEX IF NOT EXISTS assets_company_object_key_uq
            ON assets(company_id, object_key);

        CREATE TABLE IF NOT EXISTS issue_attachments (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
            asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
            issue_comment_id TEXT REFERENCES issue_comments(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS issue_attachments_company_issue_idx
            ON issue_attachments(company_id, issue_id);
        CREATE INDEX IF NOT EXISTS issue_attachments_issue_comment_idx
            ON issue_attachments(issue_comment_id);
        CREATE UNIQUE INDEX IF NOT EXISTS issue_attachments_asset_uq
            ON issue_attachments(asset_id);

        CREATE TABLE IF NOT EXISTS heartbeat_run_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            run_id TEXT NOT NULL REFERENCES heartbeat_runs(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            stream TEXT,
            level TEXT,
            color TEXT,
            message TEXT,
            payload TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (payload IS NULL OR json_valid(payload))
        );
        CREATE INDEX IF NOT EXISTS heartbeat_run_events_run_seq_idx
            ON heartbeat_run_events(run_id, seq);
        CREATE INDEX IF NOT EXISTS heartbeat_run_events_company_run_idx
            ON heartbeat_run_events(company_id, run_id);
        CREATE INDEX IF NOT EXISTS heartbeat_run_events_company_created_idx
            ON heartbeat_run_events(company_id, created_at);

        CREATE TABLE IF NOT EXISTS cost_events (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            issue_id TEXT REFERENCES issues(id) ON DELETE SET NULL,
            project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
            goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
            billing_code TEXT,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cost_cents INTEGER NOT NULL,
            occurred_at TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS cost_events_company_occurred_idx
            ON cost_events(company_id, occurred_at);
        CREATE INDEX IF NOT EXISTS cost_events_company_agent_occurred_idx
            ON cost_events(company_id, agent_id, occurred_at);

        CREATE TABLE IF NOT EXISTS approval_comments (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            approval_id TEXT NOT NULL REFERENCES approvals(id) ON DELETE CASCADE,
            author_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            author_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            body TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS approval_comments_company_idx
            ON approval_comments(company_id);
        CREATE INDEX IF NOT EXISTS approval_comments_approval_idx
            ON approval_comments(approval_id);
        CREATE INDEX IF NOT EXISTS approval_comments_approval_created_idx
            ON approval_comments(approval_id, created_at);

        CREATE TABLE IF NOT EXISTS activity_log (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            actor_type TEXT NOT NULL DEFAULT 'system',
            actor_id TEXT NOT NULL,
            action TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            run_id TEXT REFERENCES heartbeat_runs(id) ON DELETE SET NULL,
            details TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (details IS NULL OR json_valid(details))
        );
        CREATE INDEX IF NOT EXISTS activity_log_company_created_idx
            ON activity_log(company_id, created_at);
        CREATE INDEX IF NOT EXISTS activity_log_run_id_idx
            ON activity_log(run_id);
        CREATE INDEX IF NOT EXISTS activity_log_entity_type_id_idx
            ON activity_log(entity_type, entity_id);

        CREATE TABLE IF NOT EXISTS company_secrets (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            provider TEXT NOT NULL DEFAULT 'local_encrypted',
            external_ref TEXT,
            latest_version INTEGER NOT NULL DEFAULT 1,
            description TEXT,
            created_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            created_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS company_secrets_company_idx
            ON company_secrets(company_id);
        CREATE INDEX IF NOT EXISTS company_secrets_company_provider_idx
            ON company_secrets(company_id, provider);
        CREATE UNIQUE INDEX IF NOT EXISTS company_secrets_company_name_uq
            ON company_secrets(company_id, name);

        CREATE TABLE IF NOT EXISTS company_secret_versions (
            id TEXT PRIMARY KEY,
            secret_id TEXT NOT NULL REFERENCES company_secrets(id) ON DELETE CASCADE,
            version INTEGER NOT NULL,
            material TEXT NOT NULL,
            value_sha256 TEXT NOT NULL,
            created_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            created_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            revoked_at TEXT,
            CHECK (json_valid(material))
        );
        CREATE INDEX IF NOT EXISTS company_secret_versions_secret_idx
            ON company_secret_versions(secret_id, created_at);
        CREATE INDEX IF NOT EXISTS company_secret_versions_value_sha256_idx
            ON company_secret_versions(value_sha256);
        CREATE UNIQUE INDEX IF NOT EXISTS company_secret_versions_secret_version_uq
            ON company_secret_versions(secret_id, version);

        CREATE TABLE IF NOT EXISTS workspace_runtime_services (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
            project_workspace_id TEXT REFERENCES project_workspaces(id) ON DELETE SET NULL,
            issue_id TEXT REFERENCES issues(id) ON DELETE SET NULL,
            scope_type TEXT NOT NULL,
            scope_id TEXT,
            service_name TEXT NOT NULL,
            status TEXT NOT NULL,
            lifecycle TEXT NOT NULL,
            reuse_key TEXT,
            command TEXT,
            cwd TEXT,
            port INTEGER,
            url TEXT,
            provider TEXT NOT NULL,
            provider_ref TEXT,
            owner_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            started_by_run_id TEXT REFERENCES heartbeat_runs(id) ON DELETE SET NULL,
            last_used_at TEXT NOT NULL DEFAULT (datetime('now')),
            started_at TEXT NOT NULL DEFAULT (datetime('now')),
            stopped_at TEXT,
            stop_policy TEXT,
            health_status TEXT NOT NULL DEFAULT 'unknown',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (stop_policy IS NULL OR json_valid(stop_policy))
        );
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_workspace_status_idx
            ON workspace_runtime_services(company_id, project_workspace_id, status);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_project_status_idx
            ON workspace_runtime_services(company_id, project_id, status);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_run_idx
            ON workspace_runtime_services(started_by_run_id);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_updated_idx
            ON workspace_runtime_services(company_id, updated_at);
        ",
    )?;

    let sessions_table = session_table_name(conn)?;
    add_column_if_missing(
        conn,
        sessions_table,
        "company_id",
        "company_id TEXT REFERENCES companies(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        sessions_table,
        "project_id",
        "project_id TEXT REFERENCES projects(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        sessions_table,
        "issue_id",
        "issue_id TEXT REFERENCES issues(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        sessions_table,
        "agent_id",
        "agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        sessions_table,
        "workspace_type",
        "workspace_type TEXT NOT NULL DEFAULT 'legacy'",
    )?;
    add_column_if_missing(
        conn,
        sessions_table,
        "workspace_status",
        "workspace_status TEXT NOT NULL DEFAULT 'active'",
    )?;
    add_column_if_missing(
        conn,
        sessions_table,
        "workspace_repo_path",
        "workspace_repo_path TEXT",
    )?;
    add_column_if_missing(
        conn,
        sessions_table,
        "workspace_branch",
        "workspace_branch TEXT",
    )?;
    add_column_if_missing(
        conn,
        sessions_table,
        "workspace_metadata",
        "workspace_metadata TEXT DEFAULT '{}' CHECK (json_valid(workspace_metadata))",
    )?;

    let index_prefix = if sessions_table == SESSION_TABLE_RENAMED {
        "idx_local_llm_conversations"
    } else {
        "idx_agent_coding_sessions"
    };
    conn.execute_batch(&format!(
        "
        CREATE INDEX IF NOT EXISTS {index_prefix}_company_id
            ON {sessions_table}(company_id);
        CREATE INDEX IF NOT EXISTS {index_prefix}_project_id
            ON {sessions_table}(project_id);
        CREATE INDEX IF NOT EXISTS {index_prefix}_issue_id
            ON {sessions_table}(issue_id);
        CREATE INDEX IF NOT EXISTS {index_prefix}_agent_id
            ON {sessions_table}(agent_id);
        CREATE INDEX IF NOT EXISTS {index_prefix}_workspace_type
            ON {sessions_table}(workspace_type);
        CREATE INDEX IF NOT EXISTS {index_prefix}_workspace_status
            ON {sessions_table}(workspace_status);
        "
    ))?;

    Ok(())
}

/// V12: Add the Unbound local board schema ported from Paperclip.
fn migrate_v12_board_schema(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v12: board_schema");

    ensure_board_schema(conn)?;

    record_migration(conn, 12, "board_schema")?;
    Ok(())
}

fn ensure_session_agent_metadata(conn: &Connection) -> DatabaseResult<()> {
    let sessions_table = session_table_name(conn)?;
    add_column_if_missing(conn, sessions_table, "agent_id", "agent_id TEXT")?;
    add_column_if_missing(
        conn,
        sessions_table,
        "agent_name",
        "agent_name TEXT",
    )?;
    Ok(())
}

fn ensure_session_issue_metadata(conn: &Connection) -> DatabaseResult<()> {
    let sessions_table = session_table_name(conn)?;
    add_column_if_missing(conn, sessions_table, "issue_id", "issue_id TEXT")?;
    add_column_if_missing(
        conn,
        sessions_table,
        "issue_title",
        "issue_title TEXT",
    )?;
    add_column_if_missing(conn, sessions_table, "issue_url", "issue_url TEXT")?;
    Ok(())
}

fn ensure_session_provider_metadata(conn: &Connection) -> DatabaseResult<()> {
    let sessions_table = session_table_name(conn)?;
    add_column_if_missing(conn, sessions_table, "provider", "provider TEXT")?;
    add_column_if_missing(
        conn,
        sessions_table,
        "provider_session_id",
        "provider_session_id TEXT",
    )?;
    conn.execute(
        &format!(
            "UPDATE {sessions_table}
             SET provider = 'claude',
                 provider_session_id = claude_session_id
             WHERE claude_session_id IS NOT NULL
               AND TRIM(claude_session_id) != ''
               AND (
                   provider IS NULL
                   OR TRIM(provider) = ''
                   OR provider_session_id IS NULL
                   OR TRIM(provider_session_id) = ''
               )"
        ),
        [],
    )?;
    Ok(())
}

/// V13: Persist stable cross-project agent metadata on sessions.
fn migrate_v13_session_agent_metadata(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v13: session agent metadata");

    ensure_session_agent_metadata(conn)?;

    record_migration(conn, 13, "session_agent_metadata")?;
    Ok(())
}

/// V14: Persist issue linkage on sessions created from issue-driven agents.
fn migrate_v14_session_issue_metadata(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v14: session issue metadata");

    ensure_session_issue_metadata(conn)?;

    record_migration(conn, 14, "session_issue_metadata")?;
    Ok(())
}

/// V15: Reconcile local databases that may have taken either the board-schema
/// path or the earlier session-metadata-only path before those histories merged.
fn migrate_v15_reconcile_board_and_session_metadata(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v15: reconcile board and session metadata");

    ensure_board_schema(conn)?;
    ensure_session_agent_metadata(conn)?;
    ensure_session_issue_metadata(conn)?;

    record_migration(conn, 15, "reconcile_board_and_session_metadata")?;
    Ok(())
}

/// V16: Rename heartbeat run tables to agent run tables and add wake_reason.
fn migrate_v16_agent_runs_rename(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v16: agent_runs_rename");

    if table_exists(conn, "heartbeat_runs")? && !table_exists(conn, "agent_runs")? {
        conn.execute_batch("ALTER TABLE heartbeat_runs RENAME TO agent_runs;")?;
    }

    if table_exists(conn, "heartbeat_run_events")? && !table_exists(conn, "agent_run_events")? {
        conn.execute_batch("ALTER TABLE heartbeat_run_events RENAME TO agent_run_events;")?;
    }

    add_column_if_missing(conn, "agent_runs", "wake_reason", "wake_reason TEXT")?;

    conn.execute_batch(
        "
        DROP INDEX IF EXISTS heartbeat_runs_company_agent_started_idx;
        CREATE INDEX IF NOT EXISTS agent_runs_company_agent_started_idx
            ON agent_runs(company_id, agent_id, started_at);
        CREATE INDEX IF NOT EXISTS agent_runs_agent_status_created_idx
            ON agent_runs(agent_id, status, created_at);
        CREATE INDEX IF NOT EXISTS agent_runs_wakeup_request_idx
            ON agent_runs(wakeup_request_id);

        DROP INDEX IF EXISTS heartbeat_run_events_run_seq_idx;
        DROP INDEX IF EXISTS heartbeat_run_events_company_run_idx;
        DROP INDEX IF EXISTS heartbeat_run_events_company_created_idx;
        CREATE INDEX IF NOT EXISTS agent_run_events_run_seq_idx
            ON agent_run_events(run_id, seq);
        CREATE INDEX IF NOT EXISTS agent_run_events_company_run_idx
            ON agent_run_events(company_id, run_id);
        CREATE INDEX IF NOT EXISTS agent_run_events_company_created_idx
            ON agent_run_events(company_id, created_at);
        ",
    )?;

    record_migration(conn, 16, "agent_runs_rename")?;
    Ok(())
}

/// V17: Link agent runs directly to issues and persist targeted agents on comments.
fn migrate_v17_issue_linked_runs_and_comment_targets(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v17: issue_linked_runs_and_comment_targets");

    add_column_if_missing(
        conn,
        "agent_runs",
        "issue_id",
        "issue_id TEXT REFERENCES issues(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        "issue_comments",
        "target_agent_id",
        "target_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL",
    )?;

    conn.execute_batch(
        "
        CREATE INDEX IF NOT EXISTS agent_runs_issue_created_idx
            ON agent_runs(issue_id, created_at);
        CREATE INDEX IF NOT EXISTS issue_comments_target_agent_idx
            ON issue_comments(target_agent_id);

        UPDATE agent_runs
        SET issue_id = COALESCE(
            issue_id,
            json_extract(context_snapshot, '$.issue_id'),
            json_extract(context_snapshot, '$.payload.issue_id'),
            (
                SELECT i.id
                FROM issues i
                WHERE i.execution_run_id = agent_runs.id
                   OR i.checkout_run_id = agent_runs.id
                LIMIT 1
            )
        )
        WHERE issue_id IS NULL;
        ",
    )?;

    record_migration(conn, 17, "issue_linked_runs_and_comment_targets")?;
    Ok(())
}

/// V18: Persist provider-neutral session resume metadata.
fn migrate_v18_session_provider_metadata(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v18: session_provider_metadata");

    ensure_session_provider_metadata(conn)?;

    record_migration(conn, 18, "session_provider_metadata")?;
    Ok(())
}

/// V19: Remove unused board-era tables and polymorphic columns.
fn migrate_v19_prune_unused_board_schema(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v19: prune_unused_board_schema");

    conn.execute_batch("PRAGMA foreign_keys=OFF; BEGIN IMMEDIATE;")?;

    let migration_result = conn.execute_batch(
        "
        DROP INDEX IF EXISTS idx_issue_attachments_issue_comment_idx;
        DROP INDEX IF EXISTS activity_log_entity_type_id_idx;

        DROP TABLE IF EXISTS project_goals;
        DROP TABLE IF EXISTS issue_comments;
        DROP TABLE IF EXISTS company_memberships;
        DROP TABLE IF EXISTS principal_permission_grants;
        DROP TABLE IF EXISTS heartbeat_run_events;
        DROP TABLE IF EXISTS heartbeat_runs;
        DROP TABLE IF EXISTS goals;

        DROP TABLE IF EXISTS projects_new;
        CREATE TABLE projects_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'backlog',
            lead_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            target_date TEXT,
            color TEXT,
            execution_workspace_policy TEXT,
            archived_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (execution_workspace_policy IS NULL OR json_valid(execution_workspace_policy))
        );
        INSERT INTO projects_new (
            id, company_id, name, description, status, lead_agent_id, target_date,
            color, execution_workspace_policy, archived_at, created_at, updated_at
        )
        SELECT
            id, company_id, name, description, status, lead_agent_id, target_date,
            color, execution_workspace_policy, archived_at, created_at, updated_at
        FROM projects;
        DROP TABLE projects;
        ALTER TABLE projects_new RENAME TO projects;
        CREATE INDEX IF NOT EXISTS projects_company_idx
            ON projects(company_id);

        DROP TABLE IF EXISTS issues_new;
        CREATE TABLE issues_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
            parent_id TEXT REFERENCES issues(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'backlog',
            priority TEXT NOT NULL DEFAULT 'medium',
            assignee_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            assignee_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            checkout_run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL,
            execution_run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL,
            execution_agent_name_key TEXT,
            execution_locked_at TEXT,
            created_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            created_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            issue_number INTEGER,
            identifier TEXT,
            request_depth INTEGER NOT NULL DEFAULT 0,
            billing_code TEXT,
            assignee_adapter_overrides TEXT,
            execution_workspace_settings TEXT,
            started_at TEXT,
            completed_at TEXT,
            cancelled_at TEXT,
            hidden_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (assignee_adapter_overrides IS NULL OR json_valid(assignee_adapter_overrides)),
            CHECK (execution_workspace_settings IS NULL OR json_valid(execution_workspace_settings))
        );
        INSERT INTO issues_new (
            id, company_id, project_id, parent_id, title, description, status, priority,
            assignee_agent_id, assignee_user_id, checkout_run_id, execution_run_id,
            execution_agent_name_key, execution_locked_at, created_by_agent_id,
            created_by_user_id, issue_number, identifier, request_depth, billing_code,
            assignee_adapter_overrides, execution_workspace_settings, started_at,
            completed_at, cancelled_at, hidden_at, created_at, updated_at
        )
        SELECT
            id, company_id, project_id, parent_id, title, description, status, priority,
            assignee_agent_id, assignee_user_id, checkout_run_id, execution_run_id,
            execution_agent_name_key, execution_locked_at, created_by_agent_id,
            created_by_user_id, issue_number, identifier, request_depth, billing_code,
            assignee_adapter_overrides, execution_workspace_settings, started_at,
            completed_at, cancelled_at, hidden_at, created_at, updated_at
        FROM issues;
        DROP TABLE issues;
        ALTER TABLE issues_new RENAME TO issues;
        CREATE INDEX IF NOT EXISTS issues_company_status_idx
            ON issues(company_id, status);
        CREATE INDEX IF NOT EXISTS issues_company_assignee_status_idx
            ON issues(company_id, assignee_agent_id, status);
        CREATE INDEX IF NOT EXISTS issues_company_assignee_user_status_idx
            ON issues(company_id, assignee_user_id, status);
        CREATE INDEX IF NOT EXISTS issues_company_parent_idx
            ON issues(company_id, parent_id);
        CREATE INDEX IF NOT EXISTS issues_company_project_idx
            ON issues(company_id, project_id);
        CREATE UNIQUE INDEX IF NOT EXISTS issues_identifier_idx
            ON issues(identifier);

        DROP TABLE IF EXISTS cost_events_new;
        CREATE TABLE cost_events_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            issue_id TEXT REFERENCES issues(id) ON DELETE SET NULL,
            project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
            billing_code TEXT,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cost_cents INTEGER NOT NULL,
            occurred_at TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        INSERT INTO cost_events_new (
            id, company_id, agent_id, issue_id, project_id, billing_code,
            provider, model, input_tokens, output_tokens, cost_cents, occurred_at, created_at
        )
        SELECT
            id, company_id, agent_id, issue_id, project_id, billing_code,
            provider, model, input_tokens, output_tokens, cost_cents, occurred_at, created_at
        FROM cost_events;
        DROP TABLE cost_events;
        ALTER TABLE cost_events_new RENAME TO cost_events;
        CREATE INDEX IF NOT EXISTS cost_events_company_occurred_idx
            ON cost_events(company_id, occurred_at);
        CREATE INDEX IF NOT EXISTS cost_events_company_agent_occurred_idx
            ON cost_events(company_id, agent_id, occurred_at);

        DROP TABLE IF EXISTS issue_attachments_new;
        CREATE TABLE issue_attachments_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            issue_id TEXT NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
            asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        INSERT INTO issue_attachments_new (
            id, company_id, issue_id, asset_id, created_at, updated_at
        )
        SELECT
            id, company_id, issue_id, asset_id, created_at, updated_at
        FROM issue_attachments;
        DROP TABLE issue_attachments;
        ALTER TABLE issue_attachments_new RENAME TO issue_attachments;
        CREATE INDEX IF NOT EXISTS issue_attachments_company_issue_idx
            ON issue_attachments(company_id, issue_id);
        CREATE UNIQUE INDEX IF NOT EXISTS issue_attachments_asset_uq
            ON issue_attachments(asset_id);

        DROP TABLE IF EXISTS agent_wakeup_requests_new;
        CREATE TABLE agent_wakeup_requests_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            source TEXT NOT NULL,
            trigger_detail TEXT,
            reason TEXT,
            payload TEXT,
            status TEXT NOT NULL DEFAULT 'queued',
            coalesced_count INTEGER NOT NULL DEFAULT 0,
            idempotency_key TEXT,
            run_id TEXT,
            requested_at TEXT NOT NULL DEFAULT (datetime('now')),
            claimed_at TEXT,
            finished_at TEXT,
            error TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (payload IS NULL OR json_valid(payload))
        );
        INSERT INTO agent_wakeup_requests_new (
            id, company_id, agent_id, source, trigger_detail, reason, payload,
            status, coalesced_count, idempotency_key, run_id, requested_at, claimed_at,
            finished_at, error, created_at, updated_at
        )
        SELECT
            id, company_id, agent_id, source, trigger_detail, reason, payload,
            status, coalesced_count, idempotency_key, run_id, requested_at, claimed_at,
            finished_at, error, created_at, updated_at
        FROM agent_wakeup_requests;
        DROP TABLE agent_wakeup_requests;
        ALTER TABLE agent_wakeup_requests_new RENAME TO agent_wakeup_requests;
        CREATE INDEX IF NOT EXISTS agent_wakeup_requests_company_agent_status_idx
            ON agent_wakeup_requests(company_id, agent_id, status);
        CREATE INDEX IF NOT EXISTS agent_wakeup_requests_company_requested_idx
            ON agent_wakeup_requests(company_id, requested_at);
        CREATE INDEX IF NOT EXISTS agent_wakeup_requests_agent_requested_idx
            ON agent_wakeup_requests(agent_id, requested_at);

        DROP TABLE IF EXISTS activity_log_new;
        CREATE TABLE activity_log_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            actor_type TEXT NOT NULL DEFAULT 'system',
            action TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL,
            details TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (details IS NULL OR json_valid(details))
        );
        INSERT INTO activity_log_new (
            id, company_id, actor_type, action, entity_type, agent_id, run_id, details, created_at
        )
        SELECT
            id, company_id, actor_type, action, entity_type, agent_id, run_id, details, created_at
        FROM activity_log;
        DROP TABLE activity_log;
        ALTER TABLE activity_log_new RENAME TO activity_log;
        CREATE INDEX IF NOT EXISTS activity_log_company_created_idx
            ON activity_log(company_id, created_at);
        CREATE INDEX IF NOT EXISTS activity_log_run_id_idx
            ON activity_log(run_id);
        CREATE INDEX IF NOT EXISTS activity_log_entity_type_idx
            ON activity_log(entity_type);

        DROP TABLE IF EXISTS workspace_runtime_services_new;
        CREATE TABLE workspace_runtime_services_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
            project_workspace_id TEXT REFERENCES project_workspaces(id) ON DELETE SET NULL,
            issue_id TEXT REFERENCES issues(id) ON DELETE SET NULL,
            scope_type TEXT NOT NULL,
            service_name TEXT NOT NULL,
            status TEXT NOT NULL,
            lifecycle TEXT NOT NULL,
            reuse_key TEXT,
            command TEXT,
            cwd TEXT,
            port INTEGER,
            url TEXT,
            provider TEXT NOT NULL,
            provider_ref TEXT,
            owner_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            started_by_run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL,
            last_used_at TEXT NOT NULL DEFAULT (datetime('now')),
            started_at TEXT NOT NULL DEFAULT (datetime('now')),
            stopped_at TEXT,
            stop_policy TEXT,
            health_status TEXT NOT NULL DEFAULT 'unknown',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (stop_policy IS NULL OR json_valid(stop_policy))
        );
        INSERT INTO workspace_runtime_services_new (
            id, company_id, project_id, project_workspace_id, issue_id, scope_type,
            service_name, status, lifecycle, reuse_key, command, cwd, port, url,
            provider, provider_ref, owner_agent_id, started_by_run_id, last_used_at,
            started_at, stopped_at, stop_policy, health_status, created_at, updated_at
        )
        SELECT
            id, company_id, project_id, project_workspace_id, issue_id, scope_type,
            service_name, status, lifecycle, reuse_key, command, cwd, port, url,
            provider, provider_ref, owner_agent_id, started_by_run_id, last_used_at,
            started_at, stopped_at, stop_policy, health_status, created_at, updated_at
        FROM workspace_runtime_services;
        DROP TABLE workspace_runtime_services;
        ALTER TABLE workspace_runtime_services_new RENAME TO workspace_runtime_services;
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_workspace_status_idx
            ON workspace_runtime_services(company_id, project_workspace_id, status);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_project_status_idx
            ON workspace_runtime_services(company_id, project_id, status);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_run_idx
            ON workspace_runtime_services(started_by_run_id);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_updated_idx
            ON workspace_runtime_services(company_id, updated_at);
        ",
    );

    match migration_result {
        Ok(()) => {
            conn.execute_batch("COMMIT; PRAGMA foreign_keys=ON;")?;
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK; PRAGMA foreign_keys=ON;");
            return Err(error.into());
        }
    }

    record_migration(conn, 19, "prune_unused_board_schema")?;
    Ok(())
}

/// V20: Rename local coding-session tables to local LLM conversation terminology.
fn migrate_v20_rename_local_llm_conversation_tables(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v20: rename_local_llm_conversation_tables");

    let table_renames = [
        ("agent_coding_sessions", "local_llm_conversations"),
        (
            "agent_coding_session_state",
            "local_llm_conversation_state",
        ),
        (
            "agent_coding_session_messages",
            "local_llm_conversation_messages",
        ),
        (
            "agent_coding_session_event_outbox",
            "local_llm_conversation_event_outbox",
        ),
        (
            "agent_coding_session_image_uploads",
            "local_llm_conversation_image_uploads",
        ),
        (
            "agent_coding_session_attachments",
            "local_llm_conversation_attachments",
        ),
        (
            "agent_coding_session_events",
            "local_llm_conversation_events",
        ),
        ("session_secrets", "local_llm_conversation_secrets"),
    ];

    for (legacy_name, renamed_name) in table_renames {
        if table_exists(conn, legacy_name)? && !table_exists(conn, renamed_name)? {
            conn.execute_batch(&format!(
                "ALTER TABLE {legacy_name} RENAME TO {renamed_name};"
            ))?;
        }
    }

    if table_exists(conn, "local_llm_conversations")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_repository_id
                ON local_llm_conversations(repository_id);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_status
                ON local_llm_conversations(status);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_last_accessed_at
                ON local_llm_conversations(last_accessed_at);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_is_worktree
                ON local_llm_conversations(is_worktree);
            ",
        )?;
    }

    if table_exists(conn, "local_llm_conversation_messages")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_messages_session_id
                ON local_llm_conversation_messages(session_id);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_messages_session_seq
                ON local_llm_conversation_messages(session_id, sequence_number);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_messages_timestamp
                ON local_llm_conversation_messages(timestamp);
            ",
        )?;
    }

    if table_exists(conn, "local_llm_conversation_event_outbox")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_outbox_session_seq
                ON local_llm_conversation_event_outbox(session_id, sequence_number);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_outbox_status
                ON local_llm_conversation_event_outbox(status);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_outbox_batch_id
                ON local_llm_conversation_event_outbox(relay_send_batch_id);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_outbox_message_id
                ON local_llm_conversation_event_outbox(message_id);
            ",
        )?;
    }

    if table_exists(conn, "local_llm_conversation_image_uploads")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_image_uploads_session_id
                ON local_llm_conversation_image_uploads(session_id);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_image_uploads_message_id
                ON local_llm_conversation_image_uploads(message_id);
            ",
        )?;
    }

    if table_exists(conn, "local_llm_conversation_attachments")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_attachments_session_id
                ON local_llm_conversation_attachments(session_id);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_attachments_message_id
                ON local_llm_conversation_attachments(message_id);
            CREATE INDEX IF NOT EXISTS idx_local_llm_conversation_attachments_file_type
                ON local_llm_conversation_attachments(file_type);
            ",
        )?;
    }

    record_migration(conn, 20, "rename_local_llm_conversation_tables")?;
    Ok(())
}

/// V21: Rename board issue tables to task table names.
fn migrate_v21_rename_issue_tables_to_tasks(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v21: rename_issue_tables_to_tasks");

    let table_renames = [
        ("issues", "tasks"),
        ("issue_labels", "task_labels"),
        ("issue_approvals", "task_approvals"),
        ("issue_read_states", "task_read_states"),
        ("issue_attachments", "task_attachments"),
        ("issue_comments", "task_comments"),
    ];

    for (legacy_name, renamed_name) in table_renames {
        if table_exists(conn, legacy_name)? && !table_exists(conn, renamed_name)? {
            conn.execute_batch(&format!(
                "ALTER TABLE {legacy_name} RENAME TO {renamed_name};"
            ))?;
        }
    }

    conn.execute_batch(
        "
        DROP INDEX IF EXISTS issues_company_status_idx;
        DROP INDEX IF EXISTS issues_company_assignee_status_idx;
        DROP INDEX IF EXISTS issues_company_assignee_user_status_idx;
        DROP INDEX IF EXISTS issues_company_parent_idx;
        DROP INDEX IF EXISTS issues_company_project_idx;
        DROP INDEX IF EXISTS issues_identifier_idx;

        DROP INDEX IF EXISTS issue_labels_issue_idx;
        DROP INDEX IF EXISTS issue_labels_label_idx;
        DROP INDEX IF EXISTS issue_labels_company_idx;

        DROP INDEX IF EXISTS issue_approvals_issue_idx;
        DROP INDEX IF EXISTS issue_approvals_approval_idx;
        DROP INDEX IF EXISTS issue_approvals_company_idx;

        DROP INDEX IF EXISTS issue_read_states_company_issue_idx;
        DROP INDEX IF EXISTS issue_read_states_company_user_idx;
        DROP INDEX IF EXISTS issue_read_states_company_issue_user_idx;

        DROP INDEX IF EXISTS issue_attachments_company_issue_idx;
        DROP INDEX IF EXISTS issue_attachments_issue_comment_idx;
        DROP INDEX IF EXISTS issue_attachments_asset_uq;

        DROP INDEX IF EXISTS issue_comments_issue_idx;
        DROP INDEX IF EXISTS issue_comments_company_idx;
        DROP INDEX IF EXISTS issue_comments_company_issue_created_at_idx;
        DROP INDEX IF EXISTS issue_comments_company_author_issue_created_at_idx;
        DROP INDEX IF EXISTS issue_comments_target_agent_idx;
        ",
    )?;

    if table_exists(conn, "tasks")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS tasks_company_status_idx
                ON tasks(company_id, status);
            CREATE INDEX IF NOT EXISTS tasks_company_assignee_status_idx
                ON tasks(company_id, assignee_agent_id, status);
            CREATE INDEX IF NOT EXISTS tasks_company_assignee_user_status_idx
                ON tasks(company_id, assignee_user_id, status);
            CREATE INDEX IF NOT EXISTS tasks_company_parent_idx
                ON tasks(company_id, parent_id);
            CREATE INDEX IF NOT EXISTS tasks_company_project_idx
                ON tasks(company_id, project_id);
            CREATE UNIQUE INDEX IF NOT EXISTS tasks_identifier_idx
                ON tasks(identifier);
            ",
        )?;
    }

    if table_exists(conn, "task_labels")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS task_labels_task_idx
                ON task_labels(issue_id);
            CREATE INDEX IF NOT EXISTS task_labels_label_idx
                ON task_labels(label_id);
            CREATE INDEX IF NOT EXISTS task_labels_company_idx
                ON task_labels(company_id);
            ",
        )?;
    }

    if table_exists(conn, "task_approvals")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS task_approvals_task_idx
                ON task_approvals(issue_id);
            CREATE INDEX IF NOT EXISTS task_approvals_approval_idx
                ON task_approvals(approval_id);
            CREATE INDEX IF NOT EXISTS task_approvals_company_idx
                ON task_approvals(company_id);
            ",
        )?;
    }

    if table_exists(conn, "task_read_states")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS task_read_states_company_task_idx
                ON task_read_states(company_id, issue_id);
            CREATE INDEX IF NOT EXISTS task_read_states_company_user_idx
                ON task_read_states(company_id, user_id);
            CREATE UNIQUE INDEX IF NOT EXISTS task_read_states_company_task_user_idx
                ON task_read_states(company_id, issue_id, user_id);
            ",
        )?;
    }

    if table_exists(conn, "task_attachments")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS task_attachments_company_task_idx
                ON task_attachments(company_id, issue_id);
            CREATE UNIQUE INDEX IF NOT EXISTS task_attachments_asset_uq
                ON task_attachments(asset_id);
            ",
        )?;

        if column_names(conn, "task_attachments")?.contains("issue_comment_id") {
            conn.execute_batch(
                "
                CREATE INDEX IF NOT EXISTS task_attachments_task_comment_idx
                    ON task_attachments(issue_comment_id);
                ",
            )?;
        }
    }

    if table_exists(conn, "task_comments")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS task_comments_task_idx
                ON task_comments(issue_id);
            CREATE INDEX IF NOT EXISTS task_comments_company_idx
                ON task_comments(company_id);
            CREATE INDEX IF NOT EXISTS task_comments_company_task_created_at_idx
                ON task_comments(company_id, issue_id, created_at);
            CREATE INDEX IF NOT EXISTS task_comments_company_author_task_created_at_idx
                ON task_comments(company_id, author_user_id, issue_id, created_at);
            CREATE INDEX IF NOT EXISTS task_comments_target_agent_idx
                ON task_comments(target_agent_id);
            ",
        )?;
    }

    record_migration(conn, 21, "rename_issue_tables_to_tasks")?;
    Ok(())
}

/// V22: Rename board project tables and disambiguate local repository table names.
fn migrate_v22_rename_project_tables_to_repositories_and_worktrees(
    conn: &Connection,
) -> DatabaseResult<()> {
    info!("Applying migration v22: rename_project_tables_to_repositories_and_worktrees");

    // Move the local session repository catalog out of the generic `repositories` name
    // before promoting board `projects` to `repositories`.
    if table_exists(conn, "repositories")? && !table_exists(conn, "local_repositories")? {
        let repository_columns = column_names(conn, "repositories")?;
        if repository_columns.contains("path") {
            conn.execute_batch("ALTER TABLE repositories RENAME TO local_repositories;")?;
        }
    }

    if table_exists(conn, "projects")? && !table_exists(conn, "repositories")? {
        conn.execute_batch("ALTER TABLE projects RENAME TO repositories;")?;
    }

    if table_exists(conn, "project_workspaces")? && !table_exists(conn, "worktrees")? {
        conn.execute_batch("ALTER TABLE project_workspaces RENAME TO worktrees;")?;
    }

    conn.execute_batch(
        "
        DROP INDEX IF EXISTS idx_repositories_last_accessed_at;
        DROP INDEX IF EXISTS idx_repositories_path;
        DROP INDEX IF EXISTS projects_company_idx;
        DROP INDEX IF EXISTS project_workspaces_project_primary_idx;
        ",
    )?;

    if table_exists(conn, "local_repositories")? {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS idx_local_repositories_last_accessed_at
                ON local_repositories(last_accessed_at);
            CREATE INDEX IF NOT EXISTS idx_local_repositories_path
                ON local_repositories(path);
            ",
        )?;
    }

    if table_exists(conn, "repositories")?
        && column_names(conn, "repositories")?.contains("company_id")
    {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS repositories_company_idx
                ON repositories(company_id);
            ",
        )?;
    }

    if table_exists(conn, "worktrees")?
        && column_names(conn, "worktrees")?.contains("project_id")
        && column_names(conn, "worktrees")?.contains("is_primary")
    {
        conn.execute_batch(
            "
            CREATE INDEX IF NOT EXISTS worktrees_project_primary_idx
                ON worktrees(project_id, is_primary);
            ",
        )?;
    }

    record_migration(
        conn,
        22,
        "rename_project_tables_to_repositories_and_worktrees",
    )?;
    Ok(())
}

/// V23: Rebuild renamed tables so foreign keys target the renamed table names.
fn migrate_v23_rebuild_foreign_keys_after_table_renames(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v23: rebuild_foreign_keys_after_table_renames");

    let required_tables = [
        "local_llm_conversations",
        "tasks",
        "task_labels",
        "task_approvals",
        "task_read_states",
        "task_attachments",
        "worktrees",
        "workspace_runtime_services",
        "agent_runs",
        "cost_events",
    ];
    let has_full_schema = required_tables
        .iter()
        .all(|table_name| table_exists(conn, table_name).unwrap_or(false));
    if !has_full_schema {
        record_migration(conn, 23, "rebuild_foreign_keys_after_table_renames")?;
        return Ok(());
    }

    conn.execute_batch("PRAGMA foreign_keys=OFF; BEGIN IMMEDIATE;")?;

    let migration_result = conn.execute_batch(
        "
        DROP TABLE IF EXISTS local_llm_conversations_new;
        CREATE TABLE local_llm_conversations_new (
            id TEXT PRIMARY KEY,
            repository_id TEXT NOT NULL REFERENCES local_repositories(id) ON DELETE CASCADE,
            title TEXT NOT NULL DEFAULT 'New conversation',
            claude_session_id TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            is_worktree INTEGER NOT NULL DEFAULT 0,
            worktree_path TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            last_accessed_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            company_id TEXT REFERENCES companies(id) ON DELETE SET NULL,
            project_id TEXT REFERENCES repositories(id) ON DELETE SET NULL,
            issue_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
            agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            workspace_type TEXT NOT NULL DEFAULT 'legacy',
            workspace_status TEXT NOT NULL DEFAULT 'active',
            workspace_repo_path TEXT,
            workspace_branch TEXT,
            workspace_metadata TEXT DEFAULT '{}' CHECK (json_valid(workspace_metadata)),
            agent_name TEXT,
            issue_title TEXT,
            issue_url TEXT,
            provider TEXT,
            provider_session_id TEXT
        );
        INSERT INTO local_llm_conversations_new (
            id, repository_id, title, claude_session_id, status, is_worktree, worktree_path,
            created_at, last_accessed_at, updated_at, company_id, project_id, issue_id, agent_id,
            workspace_type, workspace_status, workspace_repo_path, workspace_branch, workspace_metadata,
            agent_name, issue_title, issue_url, provider, provider_session_id
        )
        SELECT
            id, repository_id, title, claude_session_id, status, is_worktree, worktree_path,
            created_at, last_accessed_at, updated_at, company_id, project_id, issue_id, agent_id,
            workspace_type, workspace_status, workspace_repo_path, workspace_branch, workspace_metadata,
            agent_name, issue_title, issue_url, provider, provider_session_id
        FROM local_llm_conversations;
        DROP TABLE local_llm_conversations;
        ALTER TABLE local_llm_conversations_new RENAME TO local_llm_conversations;
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_repository_id
            ON local_llm_conversations(repository_id);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_status
            ON local_llm_conversations(status);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_last_accessed_at
            ON local_llm_conversations(last_accessed_at);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_is_worktree
            ON local_llm_conversations(is_worktree);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_company_id
            ON local_llm_conversations(company_id);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_project_id
            ON local_llm_conversations(project_id);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_issue_id
            ON local_llm_conversations(issue_id);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_agent_id
            ON local_llm_conversations(agent_id);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_workspace_type
            ON local_llm_conversations(workspace_type);
        CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_workspace_status
            ON local_llm_conversations(workspace_status);

        DROP TABLE IF EXISTS tasks_new;
        CREATE TABLE tasks_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            project_id TEXT REFERENCES repositories(id) ON DELETE SET NULL,
            parent_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
            title TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL DEFAULT 'backlog',
            priority TEXT NOT NULL DEFAULT 'medium',
            assignee_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            assignee_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            checkout_run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL,
            execution_run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL,
            execution_agent_name_key TEXT,
            execution_locked_at TEXT,
            created_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            created_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            issue_number INTEGER,
            identifier TEXT,
            request_depth INTEGER NOT NULL DEFAULT 0,
            billing_code TEXT,
            assignee_adapter_overrides TEXT,
            execution_workspace_settings TEXT,
            started_at TEXT,
            completed_at TEXT,
            cancelled_at TEXT,
            hidden_at TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (assignee_adapter_overrides IS NULL OR json_valid(assignee_adapter_overrides)),
            CHECK (execution_workspace_settings IS NULL OR json_valid(execution_workspace_settings))
        );
        INSERT INTO tasks_new (
            id, company_id, project_id, parent_id, title, description, status, priority,
            assignee_agent_id, assignee_user_id, checkout_run_id, execution_run_id,
            execution_agent_name_key, execution_locked_at, created_by_agent_id, created_by_user_id,
            issue_number, identifier, request_depth, billing_code, assignee_adapter_overrides,
            execution_workspace_settings, started_at, completed_at, cancelled_at, hidden_at,
            created_at, updated_at
        )
        SELECT
            id, company_id, project_id, parent_id, title, description, status, priority,
            assignee_agent_id, assignee_user_id, checkout_run_id, execution_run_id,
            execution_agent_name_key, execution_locked_at, created_by_agent_id, created_by_user_id,
            issue_number, identifier, request_depth, billing_code, assignee_adapter_overrides,
            execution_workspace_settings, started_at, completed_at, cancelled_at, hidden_at,
            created_at, updated_at
        FROM tasks;
        DROP TABLE tasks;
        ALTER TABLE tasks_new RENAME TO tasks;
        CREATE INDEX IF NOT EXISTS tasks_company_status_idx
            ON tasks(company_id, status);
        CREATE INDEX IF NOT EXISTS tasks_company_assignee_status_idx
            ON tasks(company_id, assignee_agent_id, status);
        CREATE INDEX IF NOT EXISTS tasks_company_assignee_user_status_idx
            ON tasks(company_id, assignee_user_id, status);
        CREATE INDEX IF NOT EXISTS tasks_company_parent_idx
            ON tasks(company_id, parent_id);
        CREATE INDEX IF NOT EXISTS tasks_company_project_idx
            ON tasks(company_id, project_id);
        CREATE UNIQUE INDEX IF NOT EXISTS tasks_identifier_idx
            ON tasks(identifier);

        DROP TABLE IF EXISTS task_labels_new;
        CREATE TABLE task_labels_new (
            issue_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            label_id TEXT NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (issue_id, label_id)
        );
        INSERT INTO task_labels_new (issue_id, label_id, company_id, created_at)
        SELECT issue_id, label_id, company_id, created_at
        FROM task_labels;
        DROP TABLE task_labels;
        ALTER TABLE task_labels_new RENAME TO task_labels;
        CREATE INDEX IF NOT EXISTS task_labels_task_idx
            ON task_labels(issue_id);
        CREATE INDEX IF NOT EXISTS task_labels_label_idx
            ON task_labels(label_id);
        CREATE INDEX IF NOT EXISTS task_labels_company_idx
            ON task_labels(company_id);

        DROP TABLE IF EXISTS task_approvals_new;
        CREATE TABLE task_approvals_new (
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            issue_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            approval_id TEXT NOT NULL REFERENCES approvals(id) ON DELETE CASCADE,
            linked_by_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            linked_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (issue_id, approval_id)
        );
        INSERT INTO task_approvals_new (
            company_id, issue_id, approval_id, linked_by_agent_id, linked_by_user_id, created_at
        )
        SELECT
            company_id, issue_id, approval_id, linked_by_agent_id, linked_by_user_id, created_at
        FROM task_approvals;
        DROP TABLE task_approvals;
        ALTER TABLE task_approvals_new RENAME TO task_approvals;
        CREATE INDEX IF NOT EXISTS task_approvals_task_idx
            ON task_approvals(issue_id);
        CREATE INDEX IF NOT EXISTS task_approvals_approval_idx
            ON task_approvals(approval_id);
        CREATE INDEX IF NOT EXISTS task_approvals_company_idx
            ON task_approvals(company_id);

        DROP TABLE IF EXISTS task_read_states_new;
        CREATE TABLE task_read_states_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            issue_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            user_id TEXT NOT NULL REFERENCES auth_users(id) ON DELETE CASCADE,
            last_read_at TEXT NOT NULL DEFAULT (datetime('now')),
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        INSERT INTO task_read_states_new (
            id, company_id, issue_id, user_id, last_read_at, created_at, updated_at
        )
        SELECT
            id, company_id, issue_id, user_id, last_read_at, created_at, updated_at
        FROM task_read_states;
        DROP TABLE task_read_states;
        ALTER TABLE task_read_states_new RENAME TO task_read_states;
        CREATE INDEX IF NOT EXISTS task_read_states_company_task_idx
            ON task_read_states(company_id, issue_id);
        CREATE INDEX IF NOT EXISTS task_read_states_company_user_idx
            ON task_read_states(company_id, user_id);
        CREATE UNIQUE INDEX IF NOT EXISTS task_read_states_company_task_user_idx
            ON task_read_states(company_id, issue_id, user_id);

        DROP TABLE IF EXISTS task_attachments_new;
        CREATE TABLE task_attachments_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            issue_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        INSERT INTO task_attachments_new (
            id, company_id, issue_id, asset_id, created_at, updated_at
        )
        SELECT
            id, company_id, issue_id, asset_id, created_at, updated_at
        FROM task_attachments;
        DROP TABLE task_attachments;
        ALTER TABLE task_attachments_new RENAME TO task_attachments;
        CREATE INDEX IF NOT EXISTS task_attachments_company_task_idx
            ON task_attachments(company_id, issue_id);
        CREATE UNIQUE INDEX IF NOT EXISTS task_attachments_asset_uq
            ON task_attachments(asset_id);

        DROP TABLE IF EXISTS worktrees_new;
        CREATE TABLE worktrees_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            project_id TEXT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            cwd TEXT,
            repo_url TEXT,
            repo_ref TEXT,
            metadata TEXT,
            is_primary INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (metadata IS NULL OR json_valid(metadata))
        );
        INSERT INTO worktrees_new (
            id, company_id, project_id, name, cwd, repo_url, repo_ref, metadata,
            is_primary, created_at, updated_at
        )
        SELECT
            id, company_id, project_id, name, cwd, repo_url, repo_ref, metadata,
            is_primary, created_at, updated_at
        FROM worktrees;
        DROP TABLE worktrees;
        ALTER TABLE worktrees_new RENAME TO worktrees;
        CREATE INDEX IF NOT EXISTS worktrees_company_project_idx
            ON worktrees(company_id, project_id);
        CREATE INDEX IF NOT EXISTS worktrees_project_primary_idx
            ON worktrees(project_id, is_primary);

        DROP TABLE IF EXISTS workspace_runtime_services_new;
        CREATE TABLE workspace_runtime_services_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            project_id TEXT REFERENCES repositories(id) ON DELETE SET NULL,
            project_workspace_id TEXT REFERENCES worktrees(id) ON DELETE SET NULL,
            issue_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
            scope_type TEXT NOT NULL,
            service_name TEXT NOT NULL,
            status TEXT NOT NULL,
            lifecycle TEXT NOT NULL,
            reuse_key TEXT,
            command TEXT,
            cwd TEXT,
            port INTEGER,
            url TEXT,
            provider TEXT NOT NULL,
            provider_ref TEXT,
            owner_agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL,
            started_by_run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL,
            last_used_at TEXT NOT NULL DEFAULT (datetime('now')),
            started_at TEXT NOT NULL DEFAULT (datetime('now')),
            stopped_at TEXT,
            stop_policy TEXT,
            health_status TEXT NOT NULL DEFAULT 'unknown',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            CHECK (stop_policy IS NULL OR json_valid(stop_policy))
        );
        INSERT INTO workspace_runtime_services_new (
            id, company_id, project_id, project_workspace_id, issue_id, scope_type,
            service_name, status, lifecycle, reuse_key, command, cwd, port, url,
            provider, provider_ref, owner_agent_id, started_by_run_id, last_used_at,
            started_at, stopped_at, stop_policy, health_status, created_at, updated_at
        )
        SELECT
            id, company_id, project_id, project_workspace_id, issue_id, scope_type,
            service_name, status, lifecycle, reuse_key, command, cwd, port, url,
            provider, provider_ref, owner_agent_id, started_by_run_id, last_used_at,
            started_at, stopped_at, stop_policy, health_status, created_at, updated_at
        FROM workspace_runtime_services;
        DROP TABLE workspace_runtime_services;
        ALTER TABLE workspace_runtime_services_new RENAME TO workspace_runtime_services;
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_workspace_status_idx
            ON workspace_runtime_services(company_id, project_workspace_id, status);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_project_status_idx
            ON workspace_runtime_services(company_id, project_id, status);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_run_idx
            ON workspace_runtime_services(started_by_run_id);
        CREATE INDEX IF NOT EXISTS workspace_runtime_services_company_updated_idx
            ON workspace_runtime_services(company_id, updated_at);

        DROP TABLE IF EXISTS agent_runs_new;
        CREATE TABLE agent_runs_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            invocation_source TEXT NOT NULL DEFAULT 'on_demand',
            trigger_detail TEXT,
            status TEXT NOT NULL DEFAULT 'queued',
            started_at TEXT,
            finished_at TEXT,
            error TEXT,
            wakeup_request_id TEXT REFERENCES agent_wakeup_requests(id) ON DELETE SET NULL,
            exit_code INTEGER,
            signal TEXT,
            usage_json TEXT,
            result_json TEXT,
            session_id_before TEXT,
            session_id_after TEXT,
            log_store TEXT,
            log_ref TEXT,
            log_bytes INTEGER,
            log_sha256 TEXT,
            log_compressed INTEGER NOT NULL DEFAULT 0,
            stdout_excerpt TEXT,
            stderr_excerpt TEXT,
            error_code TEXT,
            external_run_id TEXT,
            context_snapshot TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            wake_reason TEXT,
            issue_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
            CHECK (usage_json IS NULL OR json_valid(usage_json)),
            CHECK (result_json IS NULL OR json_valid(result_json)),
            CHECK (context_snapshot IS NULL OR json_valid(context_snapshot))
        );
        INSERT INTO agent_runs_new (
            id, company_id, agent_id, invocation_source, trigger_detail, status, started_at, finished_at,
            error, wakeup_request_id, exit_code, signal, usage_json, result_json, session_id_before,
            session_id_after, log_store, log_ref, log_bytes, log_sha256, log_compressed, stdout_excerpt,
            stderr_excerpt, error_code, external_run_id, context_snapshot, created_at, updated_at,
            wake_reason, issue_id
        )
        SELECT
            id, company_id, agent_id, invocation_source, trigger_detail, status, started_at, finished_at,
            error, wakeup_request_id, exit_code, signal, usage_json, result_json, session_id_before,
            session_id_after, log_store, log_ref, log_bytes, log_sha256, log_compressed, stdout_excerpt,
            stderr_excerpt, error_code, external_run_id, context_snapshot, created_at, updated_at,
            wake_reason, issue_id
        FROM agent_runs;
        DROP TABLE agent_runs;
        ALTER TABLE agent_runs_new RENAME TO agent_runs;
        CREATE INDEX IF NOT EXISTS agent_runs_company_agent_started_idx
            ON agent_runs(company_id, agent_id, started_at);
        CREATE INDEX IF NOT EXISTS agent_runs_agent_status_created_idx
            ON agent_runs(agent_id, status, created_at);
        CREATE INDEX IF NOT EXISTS agent_runs_wakeup_request_idx
            ON agent_runs(wakeup_request_id);
        CREATE INDEX IF NOT EXISTS agent_runs_issue_created_idx
            ON agent_runs(issue_id, created_at);

        DROP TABLE IF EXISTS cost_events_new;
        CREATE TABLE cost_events_new (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
            agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
            issue_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
            project_id TEXT REFERENCES repositories(id) ON DELETE SET NULL,
            billing_code TEXT,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cost_cents INTEGER NOT NULL,
            occurred_at TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        INSERT INTO cost_events_new (
            id, company_id, agent_id, issue_id, project_id, billing_code, provider, model,
            input_tokens, output_tokens, cost_cents, occurred_at, created_at
        )
        SELECT
            id, company_id, agent_id, issue_id, project_id, billing_code, provider, model,
            input_tokens, output_tokens, cost_cents, occurred_at, created_at
        FROM cost_events;
        DROP TABLE cost_events;
        ALTER TABLE cost_events_new RENAME TO cost_events;
        CREATE INDEX IF NOT EXISTS cost_events_company_occurred_idx
            ON cost_events(company_id, occurred_at);
        CREATE INDEX IF NOT EXISTS cost_events_company_agent_occurred_idx
            ON cost_events(company_id, agent_id, occurred_at);
        ",
    );

    match migration_result {
        Ok(()) => {
            conn.execute_batch("COMMIT; PRAGMA foreign_keys=ON;")?;
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK; PRAGMA foreign_keys=ON;");
            return Err(error.into());
        }
    }

    record_migration(conn, 23, "rebuild_foreign_keys_after_table_renames")?;
    Ok(())
}

/// V24: Introduce machine/space hierarchy and annotate workspace-facing tables.
fn migrate_v24_machine_space_hierarchy(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v24: machine_space_hierarchy");

    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS machines (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS spaces (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            user_id TEXT NOT NULL,
            machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
            color TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE INDEX IF NOT EXISTS idx_spaces_machine_id
            ON spaces(machine_id);
        ",
    )?;

    for table_name in [
        "local_repositories",
        "repositories",
        "worktrees",
        "local_llm_conversations",
        "workspace_runtime_services",
        "tasks",
    ] {
        if !table_exists(conn, table_name)? {
            continue;
        }

        add_column_if_missing(
            conn,
            table_name,
            "machine_id",
            "machine_id TEXT REFERENCES machines(id) ON DELETE SET NULL",
        )?;
        add_column_if_missing(
            conn,
            table_name,
            "space_id",
            "space_id TEXT REFERENCES spaces(id) ON DELETE SET NULL",
        )?;

        conn.execute_batch(&format!(
            "
            CREATE INDEX IF NOT EXISTS idx_{table_name}_machine_id
                ON {table_name}(machine_id);
            CREATE INDEX IF NOT EXISTS idx_{table_name}_space_id
                ON {table_name}(space_id);
            "
        ))?;
    }

    record_migration(conn, 24, "machine_space_hierarchy")?;
    Ok(())
}

/// V25: Add user ownership column for spaces.
fn migrate_v25_spaces_add_user_id(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v25: spaces_add_user_id");

    if table_exists(conn, "spaces")? {
        add_column_if_missing(
            conn,
            "spaces",
            "user_id",
            "user_id TEXT NOT NULL DEFAULT ''",
        )?;
    }

    record_migration(conn, 25, "spaces_add_user_id")?;
    Ok(())
}

/// V26: Drop autonomous agent tables and remove agent FK columns from surviving tables.
///
/// Tables dropped: agents, agent_config_revisions, agent_api_keys, agent_runtime_state,
/// agent_task_sessions, agent_wakeup_requests, agent_runs, agent_run_events,
/// workspace_runtime_services.
///
/// Surviving tables rebuilt to remove FK columns pointing at agents/agent_runs:
/// - tasks: drop assignee_agent_id, created_by_agent_id, checkout_run_id, execution_run_id,
///   execution_agent_name_key, execution_locked_at
/// - local_llm_conversations: keep agent_id column but remove FK constraint to agents
/// - task_approvals: drop linked_by_agent_id
/// - cost_events: drop agent_id
/// - activity_log: drop agent_id, run_id
/// - approvals: drop requested_by_agent_id
/// - approval_comments: drop author_agent_id
/// - companies: drop ceo_agent_id, require_board_approval_for_new_agents
/// - repositories: drop lead_agent_id
fn migrate_v26_drop_agent_and_run_tables(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v26: drop_agent_and_run_tables");

    // Skip if agents table doesn't exist (already cleaned or never created).
    if !table_exists(conn, "agents")? {
        record_migration(conn, 26, "drop_agent_and_run_tables")?;
        return Ok(());
    }

    conn.execute_batch("PRAGMA foreign_keys=OFF; BEGIN IMMEDIATE;")?;

    let migration_result = (|| -> DatabaseResult<()> {
        // 1. Rebuild local_llm_conversations: keep agent_id but remove FK to agents.
        if table_exists(conn, "local_llm_conversations")? {
            conn.execute_batch(
                "
                DROP TABLE IF EXISTS local_llm_conversations_new;
                CREATE TABLE local_llm_conversations_new (
                    id TEXT PRIMARY KEY,
                    repository_id TEXT NOT NULL REFERENCES local_repositories(id) ON DELETE CASCADE,
                    title TEXT NOT NULL DEFAULT 'New conversation',
                    claude_session_id TEXT,
                    status TEXT NOT NULL DEFAULT 'active',
                    is_worktree INTEGER NOT NULL DEFAULT 0,
                    worktree_path TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    last_accessed_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    company_id TEXT REFERENCES companies(id) ON DELETE SET NULL,
                    project_id TEXT REFERENCES repositories(id) ON DELETE SET NULL,
                    issue_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
                    agent_id TEXT,
                    workspace_type TEXT NOT NULL DEFAULT 'legacy',
                    workspace_status TEXT NOT NULL DEFAULT 'active',
                    workspace_repo_path TEXT,
                    workspace_branch TEXT,
                    workspace_metadata TEXT DEFAULT '{}' CHECK (json_valid(workspace_metadata)),
                    agent_name TEXT,
                    issue_title TEXT,
                    issue_url TEXT,
                    provider TEXT,
                    provider_session_id TEXT,
                    machine_id TEXT REFERENCES machines(id) ON DELETE SET NULL,
                    space_id TEXT REFERENCES spaces(id) ON DELETE SET NULL
                );
                INSERT INTO local_llm_conversations_new (
                    id, repository_id, title, claude_session_id, status, is_worktree, worktree_path,
                    created_at, last_accessed_at, updated_at, company_id, project_id, issue_id, agent_id,
                    workspace_type, workspace_status, workspace_repo_path, workspace_branch, workspace_metadata,
                    agent_name, issue_title, issue_url, provider, provider_session_id, machine_id, space_id
                )
                SELECT
                    id, repository_id, title, claude_session_id, status, is_worktree, worktree_path,
                    created_at, last_accessed_at, updated_at, company_id, project_id, issue_id, agent_id,
                    workspace_type, workspace_status, workspace_repo_path, workspace_branch, workspace_metadata,
                    agent_name, issue_title, issue_url, provider, provider_session_id, machine_id, space_id
                FROM local_llm_conversations;
                DROP TABLE local_llm_conversations;
                ALTER TABLE local_llm_conversations_new RENAME TO local_llm_conversations;
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_repository_id
                    ON local_llm_conversations(repository_id);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_status
                    ON local_llm_conversations(status);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_last_accessed_at
                    ON local_llm_conversations(last_accessed_at);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_is_worktree
                    ON local_llm_conversations(is_worktree);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_company_id
                    ON local_llm_conversations(company_id);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_project_id
                    ON local_llm_conversations(project_id);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_issue_id
                    ON local_llm_conversations(issue_id);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_agent_id
                    ON local_llm_conversations(agent_id);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_workspace_type
                    ON local_llm_conversations(workspace_type);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_workspace_status
                    ON local_llm_conversations(workspace_status);
                ",
            )?;
        }

        // 2. Rebuild tasks: remove agent FK columns.
        if table_exists(conn, "tasks")? {
            conn.execute_batch(
                "
                DROP TABLE IF EXISTS tasks_new;
                CREATE TABLE tasks_new (
                    id TEXT PRIMARY KEY,
                    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
                    project_id TEXT REFERENCES repositories(id) ON DELETE SET NULL,
                    parent_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
                    title TEXT NOT NULL,
                    description TEXT,
                    status TEXT NOT NULL DEFAULT 'backlog',
                    priority TEXT NOT NULL DEFAULT 'medium',
                    assignee_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
                    created_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
                    issue_number INTEGER,
                    identifier TEXT,
                    request_depth INTEGER NOT NULL DEFAULT 0,
                    billing_code TEXT,
                    execution_workspace_settings TEXT,
                    started_at TEXT,
                    completed_at TEXT,
                    cancelled_at TEXT,
                    hidden_at TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    machine_id TEXT REFERENCES machines(id) ON DELETE SET NULL,
                    space_id TEXT REFERENCES spaces(id) ON DELETE SET NULL,
                    CHECK (execution_workspace_settings IS NULL OR json_valid(execution_workspace_settings))
                );
                INSERT INTO tasks_new (
                    id, company_id, project_id, parent_id, title, description, status, priority,
                    assignee_user_id, created_by_user_id,
                    issue_number, identifier, request_depth, billing_code,
                    execution_workspace_settings, started_at, completed_at, cancelled_at, hidden_at,
                    created_at, updated_at, machine_id, space_id
                )
                SELECT
                    id, company_id, project_id, parent_id, title, description, status, priority,
                    assignee_user_id, created_by_user_id,
                    issue_number, identifier, request_depth, billing_code,
                    execution_workspace_settings, started_at, completed_at, cancelled_at, hidden_at,
                    created_at, updated_at, machine_id, space_id
                FROM tasks;
                DROP TABLE tasks;
                ALTER TABLE tasks_new RENAME TO tasks;
                CREATE INDEX IF NOT EXISTS tasks_company_status_idx
                    ON tasks(company_id, status);
                CREATE INDEX IF NOT EXISTS tasks_company_assignee_user_status_idx
                    ON tasks(company_id, assignee_user_id, status);
                CREATE INDEX IF NOT EXISTS tasks_company_parent_idx
                    ON tasks(company_id, parent_id);
                CREATE INDEX IF NOT EXISTS tasks_company_project_idx
                    ON tasks(company_id, project_id);
                CREATE UNIQUE INDEX IF NOT EXISTS tasks_identifier_idx
                    ON tasks(identifier);
                ",
            )?;
        }

        // 3. Rebuild task_approvals: remove linked_by_agent_id.
        if table_exists(conn, "task_approvals")? {
            conn.execute_batch(
                "
                DROP TABLE IF EXISTS task_approvals_new;
                CREATE TABLE task_approvals_new (
                    company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
                    issue_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
                    approval_id TEXT NOT NULL REFERENCES approvals(id) ON DELETE CASCADE,
                    linked_by_user_id TEXT REFERENCES auth_users(id) ON DELETE SET NULL,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    PRIMARY KEY (issue_id, approval_id)
                );
                INSERT INTO task_approvals_new (
                    company_id, issue_id, approval_id, linked_by_user_id, created_at
                )
                SELECT
                    company_id, issue_id, approval_id, linked_by_user_id, created_at
                FROM task_approvals;
                DROP TABLE task_approvals;
                ALTER TABLE task_approvals_new RENAME TO task_approvals;
                CREATE INDEX IF NOT EXISTS task_approvals_task_idx
                    ON task_approvals(issue_id);
                CREATE INDEX IF NOT EXISTS task_approvals_approval_idx
                    ON task_approvals(approval_id);
                CREATE INDEX IF NOT EXISTS task_approvals_company_idx
                    ON task_approvals(company_id);
                ",
            )?;
        }

        // 4. Drop cost_events (entirely agent-dependent: agent_id NOT NULL).
        conn.execute_batch("DROP TABLE IF EXISTS cost_events;")?;

        // 5. Drop tables in FK-safe order (children before parents).
        conn.execute_batch(
            "
            DROP TABLE IF EXISTS agent_run_events;
            DROP TABLE IF EXISTS agent_runs;
            DROP TABLE IF EXISTS workspace_runtime_services;
            DROP TABLE IF EXISTS agent_config_revisions;
            DROP TABLE IF EXISTS agent_api_keys;
            DROP TABLE IF EXISTS agent_runtime_state;
            DROP TABLE IF EXISTS agent_task_sessions;
            DROP TABLE IF EXISTS agent_wakeup_requests;
            DROP TABLE IF EXISTS agents;
            ",
        )?;

        Ok(())
    })();

    match migration_result {
        Ok(()) => {
            conn.execute_batch("COMMIT; PRAGMA foreign_keys=ON;")?;
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK; PRAGMA foreign_keys=ON;");
            return Err(error);
        }
    }

    record_migration(conn, 26, "drop_agent_and_run_tables")?;
    Ok(())
}

/// V27: Drop all board tables, keeping only local session/repository/machine/space tables.
///
/// Tables dropped (in FK-safe order):
///   task_labels, task_approvals, task_read_states, task_attachments,
///   approval_comments, tasks, worktrees, labels, assets, approvals,
///   activity_log, company_secrets, company_secret_versions,
///   repositories (board), auth_sessions, auth_accounts, auth_verifications,
///   instance_user_roles, invites, join_requests, auth_users, companies.
///
/// local_llm_conversations is rebuilt to remove board FK columns
/// (company_id, project_id, agent_id, workspace_type, workspace_status,
/// workspace_repo_path, workspace_branch, workspace_metadata).
fn migrate_v27_drop_board_tables(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v27: drop_board_tables");

    // Skip if companies table doesn't exist (no board schema to drop).
    if !table_exists(conn, "companies")? {
        record_migration(conn, 27, "drop_board_tables")?;
        return Ok(());
    }

    conn.execute_batch("PRAGMA foreign_keys=OFF; BEGIN IMMEDIATE;")?;

    let migration_result = (|| -> DatabaseResult<()> {
        // 1. Rebuild local_llm_conversations: remove all board FK columns.
        if table_exists(conn, "local_llm_conversations")? {
            conn.execute_batch(
                "
                DROP TABLE IF EXISTS local_llm_conversations_new;
                CREATE TABLE local_llm_conversations_new (
                    id TEXT PRIMARY KEY,
                    repository_id TEXT NOT NULL REFERENCES local_repositories(id) ON DELETE CASCADE,
                    title TEXT NOT NULL DEFAULT 'New conversation',
                    claude_session_id TEXT,
                    status TEXT NOT NULL DEFAULT 'active',
                    is_worktree INTEGER NOT NULL DEFAULT 0,
                    worktree_path TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    last_accessed_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    issue_id TEXT,
                    agent_name TEXT,
                    issue_title TEXT,
                    issue_url TEXT,
                    provider TEXT,
                    provider_session_id TEXT,
                    machine_id TEXT REFERENCES machines(id) ON DELETE SET NULL,
                    space_id TEXT REFERENCES spaces(id) ON DELETE SET NULL
                );
                INSERT INTO local_llm_conversations_new (
                    id, repository_id, title, claude_session_id, status, is_worktree, worktree_path,
                    created_at, last_accessed_at, updated_at, issue_id, agent_name, issue_title,
                    issue_url, provider, provider_session_id, machine_id, space_id
                )
                SELECT
                    id, repository_id, title, claude_session_id, status, is_worktree, worktree_path,
                    created_at, last_accessed_at, updated_at, issue_id, agent_name, issue_title,
                    issue_url, provider, provider_session_id, machine_id, space_id
                FROM local_llm_conversations;
                DROP TABLE local_llm_conversations;
                ALTER TABLE local_llm_conversations_new RENAME TO local_llm_conversations;
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_repository_id
                    ON local_llm_conversations(repository_id);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_status
                    ON local_llm_conversations(status);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_last_accessed_at
                    ON local_llm_conversations(last_accessed_at);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_is_worktree
                    ON local_llm_conversations(is_worktree);
                CREATE INDEX IF NOT EXISTS idx_local_llm_conversations_issue_id
                    ON local_llm_conversations(issue_id);
                ",
            )?;
        }

        // 2. Drop all board tables in FK-safe order (children first).
        conn.execute_batch(
            "
            DROP TABLE IF EXISTS task_labels;
            DROP TABLE IF EXISTS task_approvals;
            DROP TABLE IF EXISTS task_read_states;
            DROP TABLE IF EXISTS task_attachments;
            DROP TABLE IF EXISTS approval_comments;
            DROP TABLE IF EXISTS tasks;
            DROP TABLE IF EXISTS worktrees;
            DROP TABLE IF EXISTS labels;
            DROP TABLE IF EXISTS assets;
            DROP TABLE IF EXISTS approvals;
            DROP TABLE IF EXISTS activity_log;
            DROP TABLE IF EXISTS company_secrets;
            DROP TABLE IF EXISTS company_secret_versions;
            DROP TABLE IF EXISTS repositories;
            DROP TABLE IF EXISTS auth_sessions;
            DROP TABLE IF EXISTS auth_accounts;
            DROP TABLE IF EXISTS auth_verifications;
            DROP TABLE IF EXISTS instance_user_roles;
            DROP TABLE IF EXISTS invites;
            DROP TABLE IF EXISTS join_requests;
            DROP TABLE IF EXISTS auth_users;
            DROP TABLE IF EXISTS companies;
            ",
        )?;

        Ok(())
    })();

    match migration_result {
        Ok(()) => {
            conn.execute_batch("COMMIT; PRAGMA foreign_keys=ON;")?;
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK; PRAGMA foreign_keys=ON;");
            return Err(error);
        }
    }

    record_migration(conn, 27, "drop_board_tables")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::OptionalExtension;

    fn foreign_key_targets(conn: &Connection, table_name: &str) -> Vec<String> {
        let sql = format!("PRAGMA foreign_key_list({table_name})");
        conn.prepare(&sql)
            .unwrap()
            .query_map([], |row| row.get::<_, String>(2))
            .unwrap()
            .filter_map(|row| row.ok())
            .collect()
    }

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

        assert!(tables.contains(&"local_repositories".to_string()));
        assert!(tables.contains(&"local_llm_conversations".to_string()));
        assert!(tables.contains(&"local_llm_conversation_messages".to_string()));
        assert!(tables.contains(&"local_llm_conversation_event_outbox".to_string()));
        assert!(tables.contains(&"user_settings".to_string()));
        assert!(tables.contains(&"local_llm_conversation_secrets".to_string()));
        assert!(tables.contains(&"machines".to_string()));
        assert!(tables.contains(&"spaces".to_string()));
        assert!(tables.contains(&"migrations".to_string()));

        // Board tables dropped by v27
        assert!(!tables.contains(&"companies".to_string()));
        assert!(!tables.contains(&"auth_users".to_string()));
        assert!(!tables.contains(&"repositories".to_string()));
        assert!(!tables.contains(&"worktrees".to_string()));
        assert!(!tables.contains(&"tasks".to_string()));
        assert!(!tables.contains(&"approvals".to_string()));
        assert!(!tables.contains(&"activity_log".to_string()));
        assert!(!tables.contains(&"company_secrets".to_string()));
        assert!(!tables.contains(&"goals".to_string()));
        assert!(!tables.contains(&"task_comments".to_string()));
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

        assert_eq!(version, 27);
    }

    #[test]
    fn test_messages_table_plaintext_content() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        // Verify the table has plaintext content column
        let columns: Vec<String> = conn
            .prepare("PRAGMA table_info(local_llm_conversation_messages)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1)) // Column 1 is name
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();

        // Should have content column
        assert!(
            columns.contains(&"content".to_string()),
            "content column should exist"
        );
        // Should NOT have encryption columns
        assert!(
            !columns.contains(&"role".to_string()),
            "role column should not exist"
        );
        assert!(
            !columns.contains(&"content_encrypted".to_string()),
            "content_encrypted should not exist"
        );
        assert!(
            !columns.contains(&"content_nonce".to_string()),
            "content_nonce should not exist"
        );
        assert!(
            !columns.contains(&"debugging_decrypted_payload".to_string()),
            "debugging_decrypted_payload should not exist"
        );
    }

    #[test]
    fn test_session_state_table_runtime_envelope_columns() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        let columns: Vec<String> = conn
            .prepare("PRAGMA table_info(local_llm_conversation_state)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();

        assert!(columns.contains(&"state_json".to_string()));
        assert!(columns.contains(&"updated_at_ms".to_string()));
        assert!(!columns.contains(&"agent_status".to_string()));
        assert!(!columns.contains(&"queued_commands".to_string()));
        assert!(!columns.contains(&"diff_summary".to_string()));
        assert!(!columns.contains(&"updated_at".to_string()));
    }

    #[test]
    fn test_board_session_columns_exist() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        let columns: Vec<String> = conn
            .prepare("PRAGMA table_info(local_llm_conversations)")
            .unwrap()
            .query_map([], |row| row.get(1))
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();

        // Kept columns
        assert!(columns.contains(&"issue_id".to_string()));
        assert!(columns.contains(&"issue_title".to_string()));
        assert!(columns.contains(&"issue_url".to_string()));
        assert!(columns.contains(&"agent_name".to_string()));

        // Dropped by v27
        assert!(!columns.contains(&"company_id".to_string()));
        assert!(!columns.contains(&"project_id".to_string()));
        assert!(!columns.contains(&"agent_id".to_string()));
        assert!(!columns.contains(&"workspace_type".to_string()));
        assert!(!columns.contains(&"workspace_status".to_string()));
        assert!(!columns.contains(&"workspace_repo_path".to_string()));
        assert!(!columns.contains(&"workspace_branch".to_string()));
        assert!(!columns.contains(&"workspace_metadata".to_string()));
    }

    #[test]
    fn test_v20_renamed_tables_reference_local_llm_conversations() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        for table_name in [
            "local_llm_conversation_messages",
            "local_llm_conversation_state",
            "local_llm_conversation_secrets",
            "local_llm_conversation_event_outbox",
        ] {
            let targets = foreign_key_targets(&conn, table_name);
            assert!(
                targets
                    .iter()
                    .any(|target| target == "local_llm_conversations"),
                "{table_name} should reference local_llm_conversations"
            );
            assert!(
                !targets.iter().any(|target| target == "agent_coding_sessions"),
                "{table_name} should not reference agent_coding_sessions"
            );
        }
    }

    #[test]
    fn test_v20_renames_legacy_tables_and_preserves_rows() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "
            CREATE TABLE migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            INSERT INTO migrations (version, name) VALUES (19, 'prune_unused_board_schema');

            CREATE TABLE agent_coding_sessions (
                id TEXT PRIMARY KEY,
                repository_id TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                is_worktree INTEGER NOT NULL DEFAULT 0,
                last_accessed_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE agent_coding_session_messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                sequence_number INTEGER NOT NULL,
                timestamp TEXT NOT NULL
            );
            CREATE TABLE session_secrets (
                session_id TEXT PRIMARY KEY,
                encrypted_secret BLOB NOT NULL,
                nonce BLOB NOT NULL,
                created_at TEXT NOT NULL
            );

            INSERT INTO agent_coding_sessions (
                id, repository_id, status, is_worktree, last_accessed_at, created_at, updated_at
            ) VALUES (
                'session-1', 'repo-1', 'active', 0, '2026-03-28T00:00:00Z', '2026-03-28T00:00:00Z', '2026-03-28T00:00:00Z'
            );
            INSERT INTO agent_coding_session_messages (
                id, session_id, sequence_number, timestamp
            ) VALUES (
                'message-1', 'session-1', 1, '2026-03-28T00:00:00Z'
            );
            INSERT INTO session_secrets (
                session_id, encrypted_secret, nonce, created_at
            ) VALUES (
                'session-1', X'00', X'01', '2026-03-28T00:00:00Z'
            );
            ",
        )
        .unwrap();

        run_migrations(&conn).unwrap();

        let sessions_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM local_llm_conversations", [], |row| {
                row.get(0)
            })
            .unwrap();
        let messages_after: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM local_llm_conversation_messages",
                [],
                |row| row.get(0),
            )
            .unwrap();
        let secrets_after: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM local_llm_conversation_secrets",
                [],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(sessions_after, 1);
        assert_eq!(messages_after, 1);
        assert_eq!(secrets_after, 1);

        assert!(!table_exists(&conn, "agent_coding_sessions").unwrap());
        assert!(!table_exists(&conn, "agent_coding_session_messages").unwrap());
        assert!(!table_exists(&conn, "session_secrets").unwrap());
    }

    #[test]
    fn test_v21_renamed_task_tables_exist() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        // All task tables dropped by v27
        for table_name in [
            "tasks",
            "task_labels",
            "task_approvals",
            "task_read_states",
            "task_attachments",
        ] {
            assert!(
                !table_exists(&conn, table_name).unwrap(),
                "{table_name} should have been dropped by v27"
            );
        }

        for legacy_table_name in [
            "issues",
            "issue_labels",
            "issue_approvals",
            "issue_read_states",
            "issue_attachments",
        ] {
            assert!(
                !table_exists(&conn, legacy_table_name).unwrap(),
                "{legacy_table_name} should not exist"
            );
        }
    }

    #[test]
    fn test_v21_renames_legacy_issue_tables_and_preserves_rows() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "
            CREATE TABLE migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            INSERT INTO migrations (version, name) VALUES (20, 'rename_local_llm_conversation_tables');

            CREATE TABLE issues (
                id TEXT PRIMARY KEY,
                company_id TEXT,
                status TEXT,
                assignee_agent_id TEXT,
                assignee_user_id TEXT,
                parent_id TEXT,
                project_id TEXT,
                identifier TEXT
            );
            CREATE TABLE issue_labels (
                issue_id TEXT,
                label_id TEXT,
                company_id TEXT
            );
            CREATE TABLE issue_approvals (
                issue_id TEXT,
                approval_id TEXT,
                company_id TEXT
            );
            CREATE TABLE issue_read_states (
                company_id TEXT,
                issue_id TEXT,
                user_id TEXT
            );
            CREATE TABLE issue_attachments (
                company_id TEXT,
                issue_id TEXT,
                asset_id TEXT
            );

            INSERT INTO issues (id, company_id, status, identifier) VALUES ('issue-1', 'company-1', 'todo', 'ACM-1');
            INSERT INTO issue_labels (issue_id, label_id, company_id) VALUES ('issue-1', 'label-1', 'company-1');
            INSERT INTO issue_approvals (issue_id, approval_id, company_id) VALUES ('issue-1', 'approval-1', 'company-1');
            INSERT INTO issue_read_states (company_id, issue_id, user_id) VALUES ('company-1', 'issue-1', 'user-1');
            INSERT INTO issue_attachments (company_id, issue_id, asset_id) VALUES ('company-1', 'issue-1', 'asset-1');
            ",
        )
        .unwrap();

        run_migrations(&conn).unwrap();

        let tasks_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
            .unwrap();
        let task_labels_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM task_labels", [], |row| row.get(0))
            .unwrap();
        let task_approvals_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM task_approvals", [], |row| row.get(0))
            .unwrap();
        let task_read_states_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM task_read_states", [], |row| row.get(0))
            .unwrap();
        let task_attachments_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM task_attachments", [], |row| row.get(0))
            .unwrap();

        assert_eq!(tasks_after, 1);
        assert_eq!(task_labels_after, 1);
        assert_eq!(task_approvals_after, 1);
        assert_eq!(task_read_states_after, 1);
        assert_eq!(task_attachments_after, 1);

        assert!(!table_exists(&conn, "issues").unwrap());
        assert!(!table_exists(&conn, "issue_labels").unwrap());
        assert!(!table_exists(&conn, "issue_approvals").unwrap());
        assert!(!table_exists(&conn, "issue_read_states").unwrap());
        assert!(!table_exists(&conn, "issue_attachments").unwrap());
    }

    #[test]
    fn test_v22_renamed_repository_and_worktree_tables_exist() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        // local_repositories should still exist
        assert!(table_exists(&conn, "local_repositories").unwrap());

        // board repositories and worktrees dropped by v27
        assert!(!table_exists(&conn, "repositories").unwrap());
        assert!(!table_exists(&conn, "worktrees").unwrap());

        for legacy_table_name in ["projects", "project_workspaces"] {
            assert!(
                !table_exists(&conn, legacy_table_name).unwrap(),
                "{legacy_table_name} should not exist"
            );
        }
    }

    #[test]
    fn test_v22_renames_legacy_project_tables_and_preserves_rows() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "
            CREATE TABLE migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            INSERT INTO migrations (version, name) VALUES (21, 'rename_issue_tables_to_tasks');

            CREATE TABLE repositories (
                id TEXT PRIMARY KEY,
                path TEXT,
                last_accessed_at TEXT
            );
            CREATE TABLE projects (
                id TEXT PRIMARY KEY,
                company_id TEXT
            );
            CREATE TABLE project_workspaces (
                id TEXT PRIMARY KEY,
                project_id TEXT,
                is_primary INTEGER
            );

            INSERT INTO repositories (id, path, last_accessed_at) VALUES ('local-repo-1', '/tmp/repo', '2026-03-29T00:00:00Z');
            INSERT INTO projects (id, company_id) VALUES ('project-1', 'company-1');
            INSERT INTO project_workspaces (id, project_id, is_primary) VALUES ('workspace-1', 'project-1', 1);
            ",
        )
        .unwrap();

        run_migrations(&conn).unwrap();

        let local_repositories_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM local_repositories", [], |row| row.get(0))
            .unwrap();
        let repositories_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM repositories", [], |row| row.get(0))
            .unwrap();
        let worktrees_after: i64 = conn
            .query_row("SELECT COUNT(*) FROM worktrees", [], |row| row.get(0))
            .unwrap();

        assert_eq!(local_repositories_after, 1);
        assert_eq!(repositories_after, 1);
        assert_eq!(worktrees_after, 1);

        assert!(!table_exists(&conn, "projects").unwrap());
        assert!(!table_exists(&conn, "project_workspaces").unwrap());
    }

    #[test]
    fn test_v23_foreign_keys_point_to_renamed_tables() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        let conversation_targets = foreign_key_targets(&conn, "local_llm_conversations");
        assert!(conversation_targets.iter().any(|t| t == "local_repositories"));
        // repositories and tasks FKs removed in v27
        assert!(!conversation_targets.iter().any(|t| t == "repositories"));
        assert!(!conversation_targets.iter().any(|t| t == "tasks"));
        assert!(!conversation_targets.iter().any(|t| t == "projects"));
        assert!(!conversation_targets.iter().any(|t| t == "issues"));
        // agent FK removed in v26
        assert!(!conversation_targets.iter().any(|t| t == "agents"));

        // tasks table dropped in v27
        assert!(!table_exists(&conn, "tasks").unwrap());

        // agent_runs and workspace_runtime_services dropped in v26
        assert!(!table_exists(&conn, "agent_runs").unwrap());
        assert!(!table_exists(&conn, "workspace_runtime_services").unwrap());
    }

    #[test]
    fn test_v24_machine_space_schema_exists_on_workspace_tables() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        assert!(table_exists(&conn, "machines").unwrap());
        assert!(table_exists(&conn, "spaces").unwrap());

        let space_targets = foreign_key_targets(&conn, "spaces");
        assert!(space_targets.iter().any(|target| target == "machines"));
        let space_columns = column_names(&conn, "spaces").unwrap();
        assert!(space_columns.contains("user_id"));

        // repositories, worktrees, tasks dropped by v27
        for table_name in [
            "local_repositories",
            "local_llm_conversations",
        ] {
            let columns = column_names(&conn, table_name).unwrap();
            assert!(columns.contains("machine_id"), "{table_name} missing machine_id");
            assert!(columns.contains("space_id"), "{table_name} missing space_id");

            let targets = foreign_key_targets(&conn, table_name);
            assert!(
                targets.iter().any(|target| target == "machines"),
                "{table_name} machine_id should reference machines"
            );
            assert!(
                targets.iter().any(|target| target == "spaces"),
                "{table_name} space_id should reference spaces"
            );
        }
    }

    #[test]
    fn test_full_board_table_set_exists() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        let tables: Vec<String> = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table'")
            .unwrap()
            .query_map([], |row| row.get(0))
            .unwrap()
            .filter_map(|row| row.ok())
            .collect();

        // Tables that should still exist
        for table in [
            "local_repositories",
            "machines",
            "spaces",
        ] {
            assert!(
                tables.contains(&table.to_string()),
                "missing table: {table}"
            );
        }

        // Board tables dropped by v27
        for removed_table in [
            "companies",
            "auth_users",
            "auth_sessions",
            "auth_accounts",
            "auth_verifications",
            "instance_user_roles",
            "invites",
            "join_requests",
            "repositories",
            "worktrees",
            "tasks",
            "labels",
            "task_labels",
            "task_approvals",
            "task_read_states",
            "assets",
            "task_attachments",
            "approvals",
            "approval_comments",
            "activity_log",
            "company_secrets",
            "company_secret_versions",
        ] {
            assert!(
                !tables.contains(&removed_table.to_string()),
                "{removed_table} should have been dropped by v27"
            );
        }

        // Tables removed by v26
        for removed_table in [
            "agents",
            "agent_config_revisions",
            "agent_api_keys",
            "agent_runtime_state",
            "agent_task_sessions",
            "agent_wakeup_requests",
            "agent_runs",
            "agent_run_events",
            "workspace_runtime_services",
            "cost_events",
        ] {
            assert!(
                !tables.contains(&removed_table.to_string()),
                "{removed_table} should have been dropped"
            );
        }

        // Tables removed by earlier migrations
        assert!(!tables.contains(&"heartbeat_runs".to_string()));
        assert!(!tables.contains(&"heartbeat_run_events".to_string()));
        assert!(!tables.contains(&"company_memberships".to_string()));
        assert!(!tables.contains(&"principal_permission_grants".to_string()));
        assert!(!tables.contains(&"project_goals".to_string()));
        assert!(!tables.contains(&"goals".to_string()));
        assert!(!tables.contains(&"task_comments".to_string()));
    }

    #[test]
    fn test_v26_agent_tables_dropped_and_fk_columns_removed() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        // Agent tables should not exist.
        assert!(!table_exists(&conn, "agents").unwrap());
        assert!(!table_exists(&conn, "agent_runs").unwrap());
        assert!(!table_exists(&conn, "agent_run_events").unwrap());
        assert!(!table_exists(&conn, "workspace_runtime_services").unwrap());
        assert!(!table_exists(&conn, "cost_events").unwrap());

        // tasks table dropped by v27
        assert!(!table_exists(&conn, "tasks").unwrap());

        // local_llm_conversations should not FK to agents (agent_id column also dropped by v27).
        let conv_cols = column_names(&conn, "local_llm_conversations").unwrap();
        assert!(!conv_cols.contains("agent_id"));
        let conv_targets = foreign_key_targets(&conn, "local_llm_conversations");
        assert!(!conv_targets.iter().any(|t| t == "agents"));

        // task_approvals dropped by v27
        assert!(!table_exists(&conn, "task_approvals").unwrap());
    }

    #[test]
    fn test_v19_prunes_unused_tables_and_columns() {
        let conn = Connection::open_in_memory().unwrap();
        run_migrations(&conn).unwrap();

        let tables: Vec<String> = conn
            .prepare("SELECT name FROM sqlite_master WHERE type='table'")
            .unwrap()
            .query_map([], |row| row.get(0))
            .unwrap()
            .filter_map(|row| row.ok())
            .collect();

        for table_name in [
            "goals",
            "project_goals",
            "issue_comments",
            "company_memberships",
            "principal_permission_grants",
            "heartbeat_runs",
            "heartbeat_run_events",
        ] {
            assert!(
                !tables.contains(&table_name.to_string()),
                "{table_name} should be removed"
            );
        }

        // repositories (board), tasks, task_attachments, cost_events, activity_log
        // all dropped by v27
        assert!(!table_exists(&conn, "repositories").unwrap());
        assert!(!table_exists(&conn, "tasks").unwrap());
        assert!(!table_exists(&conn, "task_attachments").unwrap());
        assert!(!table_exists(&conn, "cost_events").unwrap());
        assert!(!table_exists(&conn, "activity_log").unwrap());

        // agent_wakeup_requests and workspace_runtime_services are now dropped by v26.
        assert!(!table_exists(&conn, "agent_wakeup_requests").unwrap());
        assert!(!table_exists(&conn, "workspace_runtime_services").unwrap());
    }

    #[test]
    fn test_v16_migrates_existing_heartbeat_tables_without_data_loss() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute(
            "CREATE TABLE migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            )",
            [],
        )
        .unwrap();
        migrate_v1_initial_schema(&conn).unwrap();
        migrate_v2_outbox(&conn).unwrap();
        migrate_v3_normalize_tables(&conn).unwrap();
        migrate_v4_events_table(&conn).unwrap();
        migrate_v5_session_secrets(&conn).unwrap();
        migrate_v6_drop_events_table(&conn).unwrap();
        migrate_v7_drop_role_column(&conn).unwrap();
        migrate_v8_plaintext_messages(&conn).unwrap();
        migrate_v9_retired_cloud_outbox(&conn).unwrap();
        migrate_v10_retired_cloud_sync_state(&conn).unwrap();
        migrate_v11_session_state_runtime_envelope(&conn).unwrap();
        migrate_v12_board_schema(&conn).unwrap();

        conn.execute(
            "INSERT INTO companies (
                id, name, status, issue_prefix, issue_counter,
                budget_monthly_cents, spent_monthly_cents,
                require_board_approval_for_new_agents, created_at, updated_at
            ) VALUES (?1, 'Acme', 'active', 'ACM', 0, 0, 0, 1, ?2, ?2)",
            rusqlite::params!["company-1", "2026-03-13T00:00:00Z"],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO agents (
                id, company_id, name, slug, role, status,
                adapter_type, adapter_config, runtime_config, budget_monthly_cents,
                spent_monthly_cents, permissions, created_at, updated_at
            ) VALUES (
                ?1, ?2, 'Agent', 'agent', 'general', 'idle',
                'process', '{}', '{}', 0, 0, '{}', ?3, ?3
            )",
            rusqlite::params!["agent-1", "company-1", "2026-03-13T00:00:00Z"],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO heartbeat_runs (
                id, company_id, agent_id, invocation_source, trigger_detail, status,
                created_at, updated_at
            ) VALUES (?1, ?2, ?3, 'on_demand', 'manual', 'queued', ?4, ?4)",
            rusqlite::params!["run-1", "company-1", "agent-1", "2026-03-13T00:00:00Z"],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO heartbeat_run_events (
                company_id, run_id, agent_id, seq, event_type, message, created_at
            ) VALUES (?1, ?2, ?3, 1, 'queued', 'queued', ?4)",
            rusqlite::params!["company-1", "run-1", "agent-1", "2026-03-13T00:00:00Z"],
        )
        .unwrap();

        migrate_v16_agent_runs_rename(&conn).unwrap();

        let run_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM agent_runs WHERE id = 'run-1'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        let event_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM agent_run_events WHERE run_id = 'run-1'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        let wake_reason: Option<String> = conn
            .query_row(
                "SELECT wake_reason FROM agent_runs WHERE id = 'run-1'",
                [],
                |row| row.get(0),
            )
            .optional()
            .unwrap()
            .flatten();

        assert_eq!(run_count, 1);
        assert_eq!(event_count, 1);
        assert_eq!(wake_reason, None);
    }

    #[test]
    fn test_v17_backfills_issue_links_for_existing_agent_runs() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute(
            "CREATE TABLE migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            )",
            [],
        )
        .unwrap();
        migrate_v1_initial_schema(&conn).unwrap();
        migrate_v2_outbox(&conn).unwrap();
        migrate_v3_normalize_tables(&conn).unwrap();
        migrate_v4_events_table(&conn).unwrap();
        migrate_v5_session_secrets(&conn).unwrap();
        migrate_v6_drop_events_table(&conn).unwrap();
        migrate_v7_drop_role_column(&conn).unwrap();
        migrate_v8_plaintext_messages(&conn).unwrap();
        migrate_v9_retired_cloud_outbox(&conn).unwrap();
        migrate_v10_retired_cloud_sync_state(&conn).unwrap();
        migrate_v11_session_state_runtime_envelope(&conn).unwrap();
        migrate_v12_board_schema(&conn).unwrap();
        migrate_v13_session_agent_metadata(&conn).unwrap();
        migrate_v14_session_issue_metadata(&conn).unwrap();
        migrate_v15_reconcile_board_and_session_metadata(&conn).unwrap();
        migrate_v16_agent_runs_rename(&conn).unwrap();

        conn.execute(
            "INSERT INTO companies (
                id, name, status, issue_prefix, issue_counter,
                budget_monthly_cents, spent_monthly_cents,
                require_board_approval_for_new_agents, created_at, updated_at
            ) VALUES (?1, 'Acme', 'active', 'ACM', 0, 0, 0, 1, ?2, ?2)",
            rusqlite::params!["company-1", "2026-03-18T00:00:00Z"],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO agents (
                id, company_id, name, slug, role, status,
                adapter_type, adapter_config, runtime_config, budget_monthly_cents,
                spent_monthly_cents, permissions, created_at, updated_at
            ) VALUES (
                ?1, ?2, 'Agent', 'agent', 'general', 'idle',
                'process', '{}', '{}', 0, 0, '{}', ?3, ?3
            )",
            rusqlite::params!["agent-1", "company-1", "2026-03-18T00:00:00Z"],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO issues (
                id, company_id, title, status, priority, request_depth, created_at, updated_at
            ) VALUES (?1, ?2, 'Backfill issue', 'todo', 'medium', 0, ?3, ?3)",
            rusqlite::params!["issue-1", "company-1", "2026-03-18T00:00:00Z"],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO agent_runs (
                id, company_id, agent_id, invocation_source, trigger_detail, wake_reason,
                status, context_snapshot, created_at, updated_at
            ) VALUES (?1, ?2, ?3, 'automation', 'system', 'issue_commented', 'queued', ?4, ?5, ?5)",
            rusqlite::params![
                "run-1",
                "company-1",
                "agent-1",
                r#"{"issue_id":"issue-1","payload":{"issue_id":"issue-1"}}"#,
                "2026-03-18T00:00:00Z"
            ],
        )
        .unwrap();

        migrate_v17_issue_linked_runs_and_comment_targets(&conn).unwrap();

        let issue_id: Option<String> = conn
            .query_row(
                "SELECT issue_id FROM agent_runs WHERE id = 'run-1'",
                [],
                |row| row.get(0),
            )
            .optional()
            .unwrap()
            .flatten();

        assert_eq!(issue_id.as_deref(), Some("issue-1"));
    }
}
