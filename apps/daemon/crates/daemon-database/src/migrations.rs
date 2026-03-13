//! Database migrations.
//!
//! This module contains all SQL migrations for the database schema.
//! Migrations are run in order and tracked in the `migrations` table.

use crate::DatabaseResult;
use rusqlite::Connection;
use std::collections::HashSet;
use tracing::{debug, info};

/// Current schema version.
pub const CURRENT_VERSION: i32 = 12;

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

fn add_column_if_missing(
    conn: &Connection,
    table_name: &str,
    column_name: &str,
    column_sql: &str,
) -> DatabaseResult<()> {
    if !column_names(conn, table_name)?.contains(column_name) {
        conn.execute_batch(&format!("ALTER TABLE {table_name} ADD COLUMN {column_sql};"))?;
    }
    Ok(())
}

/// V12: Add the Unbound local board schema ported from Paperclip.
fn migrate_v12_board_schema(conn: &Connection) -> DatabaseResult<()> {
    info!("Applying migration v12: board_schema");

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

    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "company_id",
        "company_id TEXT REFERENCES companies(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "project_id",
        "project_id TEXT REFERENCES projects(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "issue_id",
        "issue_id TEXT REFERENCES issues(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "agent_id",
        "agent_id TEXT REFERENCES agents(id) ON DELETE SET NULL",
    )?;
    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "workspace_type",
        "workspace_type TEXT NOT NULL DEFAULT 'legacy'",
    )?;
    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "workspace_status",
        "workspace_status TEXT NOT NULL DEFAULT 'active'",
    )?;
    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "workspace_repo_path",
        "workspace_repo_path TEXT",
    )?;
    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "workspace_branch",
        "workspace_branch TEXT",
    )?;
    add_column_if_missing(
        conn,
        "agent_coding_sessions",
        "workspace_metadata",
        "workspace_metadata TEXT DEFAULT '{}' CHECK (json_valid(workspace_metadata))",
    )?;

    conn.execute_batch(
        "
        CREATE INDEX IF NOT EXISTS idx_agent_coding_sessions_company_id
            ON agent_coding_sessions(company_id);
        CREATE INDEX IF NOT EXISTS idx_agent_coding_sessions_project_id
            ON agent_coding_sessions(project_id);
        CREATE INDEX IF NOT EXISTS idx_agent_coding_sessions_issue_id
            ON agent_coding_sessions(issue_id);
        CREATE INDEX IF NOT EXISTS idx_agent_coding_sessions_agent_id
            ON agent_coding_sessions(agent_id);
        CREATE INDEX IF NOT EXISTS idx_agent_coding_sessions_workspace_type
            ON agent_coding_sessions(workspace_type);
        CREATE INDEX IF NOT EXISTS idx_agent_coding_sessions_workspace_status
            ON agent_coding_sessions(workspace_status);
        ",
    )?;

    record_migration(conn, 12, "board_schema")?;
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
        assert!(tables.contains(&"user_settings".to_string()));
        assert!(tables.contains(&"session_secrets".to_string()));
        assert!(tables.contains(&"companies".to_string()));
        assert!(tables.contains(&"auth_users".to_string()));
        assert!(tables.contains(&"agents".to_string()));
        assert!(tables.contains(&"projects".to_string()));
        assert!(tables.contains(&"issues".to_string()));
        assert!(tables.contains(&"issue_comments".to_string()));
        assert!(tables.contains(&"approvals".to_string()));
        assert!(tables.contains(&"activity_log".to_string()));
        assert!(tables.contains(&"company_secrets".to_string()));
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

        assert_eq!(version, 12);
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
            .prepare("PRAGMA table_info(agent_coding_session_state)")
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
            .prepare("PRAGMA table_info(agent_coding_sessions)")
            .unwrap()
            .query_map([], |row| row.get(1))
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();

        assert!(columns.contains(&"company_id".to_string()));
        assert!(columns.contains(&"project_id".to_string()));
        assert!(columns.contains(&"issue_id".to_string()));
        assert!(columns.contains(&"agent_id".to_string()));
        assert!(columns.contains(&"workspace_type".to_string()));
        assert!(columns.contains(&"workspace_status".to_string()));
        assert!(columns.contains(&"workspace_repo_path".to_string()));
        assert!(columns.contains(&"workspace_branch".to_string()));
        assert!(columns.contains(&"workspace_metadata".to_string()));
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

        for table in [
            "companies",
            "auth_users",
            "auth_sessions",
            "auth_accounts",
            "auth_verifications",
            "instance_user_roles",
            "agents",
            "company_memberships",
            "principal_permission_grants",
            "invites",
            "join_requests",
            "agent_config_revisions",
            "agent_api_keys",
            "agent_runtime_state",
            "agent_task_sessions",
            "agent_wakeup_requests",
            "projects",
            "project_workspaces",
            "workspace_runtime_services",
            "project_goals",
            "goals",
            "issues",
            "labels",
            "issue_labels",
            "issue_approvals",
            "issue_comments",
            "issue_read_states",
            "assets",
            "issue_attachments",
            "heartbeat_runs",
            "heartbeat_run_events",
            "cost_events",
            "approvals",
            "approval_comments",
            "activity_log",
            "company_secrets",
            "company_secret_versions",
        ] {
            assert!(tables.contains(&table.to_string()), "missing table: {table}");
        }
    }
}
