//
//  DatabaseMigrations.swift
//  unbound-ios
//
//  Database schema migrations using GRDB migrator.
//  All migrations must succeed or the app will not start.
//

import Foundation
import GRDB

enum DatabaseMigrations {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {

        // MARK: - v1: Initial Schema

        migrator.registerMigration("v1_initial_schema") { db in

            // repositories table
            try db.create(table: "repositories") { t in
                t.column("id", .text).primaryKey()
                t.column("path", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("last_accessed_at", .datetime).notNull()
                t.column("added_at", .datetime).notNull()
                t.column("is_git_repository", .boolean).notNull().defaults(to: false)
                t.column("sessions_path", .text)
                t.column("default_branch", .text)
                t.column("default_remote", .text)
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(indexOn: "repositories", columns: ["last_accessed_at"])
            try db.create(indexOn: "repositories", columns: ["path"])

            // sessions table
            try db.create(table: "sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("repository_id", .text)
                    .references("repositories", onDelete: .setNull)
                t.column("worktree_path", .text)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("last_accessed_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(indexOn: "sessions", columns: ["repository_id"])
            try db.create(indexOn: "sessions", columns: ["status"])
            try db.create(indexOn: "sessions", columns: ["last_accessed_at"])

            // chat_tabs table
            try db.create(table: "chat_tabs") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("title", .text).notNull().defaults(to: "New chat")
                t.column("claude_session_id", .text)
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(indexOn: "chat_tabs", columns: ["session_id"])
            try db.create(indexOn: "chat_tabs", columns: ["created_at"])

            // worktree_messages table (encrypted content)
            try db.create(table: "worktree_messages") { t in
                t.column("id", .text).primaryKey()
                t.column("chat_tab_id", .text).notNull()
                    .references("chat_tabs", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content_encrypted", .blob).notNull()
                t.column("content_nonce", .blob).notNull()
                t.column("timestamp", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("is_streaming", .boolean).notNull().defaults(to: false)
                t.column("sequence_number", .integer).notNull()
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(indexOn: "worktree_messages", columns: ["chat_tab_id"])
            try db.create(indexOn: "worktree_messages", columns: ["chat_tab_id", "sequence_number"])
            try db.create(indexOn: "worktree_messages", columns: ["timestamp"])

            // image_uploads table
            try db.create(table: "image_uploads") { t in
                t.column("id", .text).primaryKey()
                t.column("message_id", .text)
                    .references("worktree_messages", onDelete: .setNull)
                t.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("filename", .text).notNull()
                t.column("stored_filename", .text).notNull()
                t.column("mime_type", .text).notNull()
                t.column("file_size", .integer).notNull()
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("checksum", .text)
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(indexOn: "image_uploads", columns: ["session_id"])
            try db.create(indexOn: "image_uploads", columns: ["message_id"])

            // attachments table
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("message_id", .text)
                    .references("worktree_messages", onDelete: .setNull)
                t.column("session_id", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("filename", .text).notNull()
                t.column("stored_filename", .text).notNull()
                t.column("file_type", .text).notNull()
                t.column("mime_type", .text).notNull()
                t.column("file_size", .integer).notNull()
                t.column("checksum", .text)
                t.column("metadata_json", .text)
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(indexOn: "attachments", columns: ["session_id"])
            try db.create(indexOn: "attachments", columns: ["message_id"])
            try db.create(indexOn: "attachments", columns: ["file_type"])

            // user_settings table
            try db.create(table: "user_settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("value_type", .text).notNull()
                t.column("updated_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }
        }

        // MARK: - v2: Rename Tables with agent_coding_session Prefix

        migrator.registerMigration("v2_rename_agent_coding_session_tables") { db in
            // Rename sessions → agent_coding_sessions
            try db.rename(table: "sessions", to: "agent_coding_sessions")

            // Rename chat_tabs → agent_coding_session_chat_tabs
            try db.rename(table: "chat_tabs", to: "agent_coding_session_chat_tabs")

            // Rename worktree_messages → agent_coding_session_messages
            try db.rename(table: "worktree_messages", to: "agent_coding_session_messages")

            // Rename image_uploads → agent_coding_session_image_uploads
            // Need to recreate for updated FK references
            try db.rename(table: "image_uploads", to: "image_uploads_old")
            try db.create(table: "agent_coding_session_image_uploads") { t in
                t.column("id", .text).primaryKey()
                t.column("message_id", .text)
                    .references("agent_coding_session_messages", onDelete: .setNull)
                t.column("session_id", .text).notNull()
                    .references("agent_coding_sessions", onDelete: .cascade)
                t.column("filename", .text).notNull()
                t.column("stored_filename", .text).notNull()
                t.column("mime_type", .text).notNull()
                t.column("file_size", .integer).notNull()
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("checksum", .text)
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.execute(sql: "INSERT INTO agent_coding_session_image_uploads SELECT * FROM image_uploads_old")
            try db.drop(table: "image_uploads_old")

            // Rename attachments → agent_coding_session_attachments
            // Need to recreate for updated FK references
            try db.rename(table: "attachments", to: "attachments_old")
            try db.create(table: "agent_coding_session_attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("message_id", .text)
                    .references("agent_coding_session_messages", onDelete: .setNull)
                t.column("session_id", .text).notNull()
                    .references("agent_coding_sessions", onDelete: .cascade)
                t.column("filename", .text).notNull()
                t.column("stored_filename", .text).notNull()
                t.column("file_type", .text).notNull()
                t.column("mime_type", .text).notNull()
                t.column("file_size", .integer).notNull()
                t.column("checksum", .text)
                t.column("metadata_json", .text)
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.execute(sql: "INSERT INTO agent_coding_session_attachments SELECT * FROM attachments_old")
            try db.drop(table: "attachments_old")

            // Recreate indexes for agent_coding_sessions
            try db.create(indexOn: "agent_coding_sessions", columns: ["repository_id"])
            try db.create(indexOn: "agent_coding_sessions", columns: ["status"])
            try db.create(indexOn: "agent_coding_sessions", columns: ["last_accessed_at"])

            // Recreate indexes for agent_coding_session_chat_tabs
            try db.create(indexOn: "agent_coding_session_chat_tabs", columns: ["session_id"])
            try db.create(indexOn: "agent_coding_session_chat_tabs", columns: ["created_at"])

            // Recreate indexes for agent_coding_session_messages
            try db.create(indexOn: "agent_coding_session_messages", columns: ["chat_tab_id"])
            try db.create(indexOn: "agent_coding_session_messages", columns: ["chat_tab_id", "sequence_number"])
            try db.create(indexOn: "agent_coding_session_messages", columns: ["timestamp"])

            // Recreate indexes for agent_coding_session_image_uploads
            try db.create(indexOn: "agent_coding_session_image_uploads", columns: ["session_id"])
            try db.create(indexOn: "agent_coding_session_image_uploads", columns: ["message_id"])

            // Recreate indexes for agent_coding_session_attachments
            try db.create(indexOn: "agent_coding_session_attachments", columns: ["session_id"])
            try db.create(indexOn: "agent_coding_session_attachments", columns: ["message_id"])
            try db.create(indexOn: "agent_coding_session_attachments", columns: ["file_type"])
        }

        // MARK: - v3: Align Local SQLite with macOS Schema

        migrator.registerMigration("v3_align_macos_sqlite_schema") { db in
            // Rebuild sessions table to match macOS columns.
            try db.create(table: "agent_coding_sessions_new") { t in
                t.column("id", .text).primaryKey()
                t.column("repository_id", .text).notNull()
                    .references("repositories", onDelete: .cascade)
                t.column("title", .text).notNull().defaults(to: "New conversation")
                t.column("claude_session_id", .text)
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("is_worktree", .boolean).notNull().defaults(to: false)
                t.column("worktree_path", .text)
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("last_accessed_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.execute(
                sql: """
                    INSERT INTO agent_coding_sessions_new
                        (id, repository_id, title, claude_session_id, status, is_worktree, worktree_path, created_at, last_accessed_at, updated_at)
                    SELECT
                        id,
                        repository_id,
                        COALESCE(name, 'New conversation') AS title,
                        NULL AS claude_session_id,
                        status,
                        CASE
                            WHEN worktree_path IS NOT NULL AND worktree_path != '' THEN 1
                            ELSE 0
                        END AS is_worktree,
                        worktree_path,
                        created_at,
                        last_accessed_at,
                        updated_at
                    FROM agent_coding_sessions
                    WHERE repository_id IS NOT NULL
                    """
            )

            try db.drop(table: "agent_coding_sessions")
            try db.rename(table: "agent_coding_sessions_new", to: "agent_coding_sessions")

            try db.create(indexOn: "agent_coding_sessions", columns: ["repository_id"])
            try db.create(indexOn: "agent_coding_sessions", columns: ["status"])
            try db.create(indexOn: "agent_coding_sessions", columns: ["last_accessed_at"])
            try db.create(indexOn: "agent_coding_sessions", columns: ["is_worktree"])

            // Rebuild messages table to macOS plaintext schema.
            try db.create(table: "agent_coding_session_messages_new") { t in
                t.column("id", .text).primaryKey()
                t.column("session_id", .text).notNull()
                    .references("agent_coding_sessions", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("is_streaming", .boolean).notNull().defaults(to: false)
                t.column("sequence_number", .integer).notNull()
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            // Legacy iOS rows only have encrypted payloads, so content is reset when migrating.
            try db.execute(
                sql: """
                    INSERT INTO agent_coding_session_messages_new
                        (id, session_id, content, timestamp, is_streaming, sequence_number, created_at)
                    SELECT
                        m.id,
                        ct.session_id,
                        '' AS content,
                        m.timestamp,
                        m.is_streaming,
                        m.sequence_number,
                        m.created_at
                    FROM agent_coding_session_messages m
                    INNER JOIN agent_coding_session_chat_tabs ct
                        ON ct.id = m.chat_tab_id
                    """
            )

            try db.drop(table: "agent_coding_session_messages")
            try db.rename(table: "agent_coding_session_messages_new", to: "agent_coding_session_messages")

            try db.create(indexOn: "agent_coding_session_messages", columns: ["session_id"])
            try db.create(indexOn: "agent_coding_session_messages", columns: ["session_id", "sequence_number"])
            try db.create(indexOn: "agent_coding_session_messages", columns: ["timestamp"])

            // macOS does not use local chat tabs.
            try db.drop(table: "agent_coding_session_chat_tabs")

            // Add macOS runtime tables used for local state + sync.
            try db.create(table: "agent_coding_session_state", ifNotExists: true) { t in
                t.column("session_id", .text).primaryKey()
                    .references("agent_coding_sessions", onDelete: .cascade)
                t.column("agent_status", .text).notNull().defaults(to: "idle")
                t.column("queued_commands", .text)
                t.column("diff_summary", .text)
                t.column("updated_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "session_secrets", ifNotExists: true) { t in
                t.column("session_id", .text).primaryKey()
                    .references("agent_coding_sessions", onDelete: .cascade)
                t.column("encrypted_secret", .blob).notNull()
                t.column("nonce", .blob).notNull()
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "agent_coding_session_message_supabase_outbox", ifNotExists: true) { t in
                t.column("message_id", .text).primaryKey()
                    .references("agent_coding_session_messages", onDelete: .cascade)
                t.column("created_at", .datetime).notNull()
                    .defaults(sql: "CURRENT_TIMESTAMP")
                t.column("sent_at", .datetime)
                t.column("last_attempt_at", .datetime)
                t.column("retry_count", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
            }
            try db.create(indexOn: "agent_coding_session_message_supabase_outbox", columns: ["sent_at"])
            try db.create(indexOn: "agent_coding_session_message_supabase_outbox", columns: ["last_attempt_at"])

            try db.create(table: "agent_coding_session_supabase_sync_state", ifNotExists: true) { t in
                t.column("session_id", .text).primaryKey()
                    .references("agent_coding_sessions", onDelete: .cascade)
                t.column("last_synced_sequence_number", .integer).notNull().defaults(to: 0)
                t.column("last_sync_at", .datetime)
                t.column("last_error", .text)
                t.column("retry_count", .integer).notNull().defaults(to: 0)
                t.column("last_attempt_at", .datetime)
            }
            try db.create(indexOn: "agent_coding_session_supabase_sync_state", columns: ["last_attempt_at"])

            try db.create(table: "agent_coding_session_ably_sync_state", ifNotExists: true) { t in
                t.column("session_id", .text).primaryKey()
                    .references("agent_coding_sessions", onDelete: .cascade)
                t.column("last_synced_sequence_number", .integer).notNull().defaults(to: 0)
                t.column("last_sync_at", .datetime)
                t.column("last_error", .text)
                t.column("retry_count", .integer).notNull().defaults(to: 0)
                t.column("last_attempt_at", .datetime)
            }
            try db.create(indexOn: "agent_coding_session_ably_sync_state", columns: ["last_attempt_at"])

            // Mirror daemon migration tracking table name.
            try db.create(table: "migrations", ifNotExists: true) { t in
                t.column("version", .integer).primaryKey()
                t.column("name", .text).notNull()
                t.column("applied_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }

        // MARK: - v4: Add device_id to Sessions

        migrator.registerMigration("v4_add_device_id_to_sessions") { db in
            try db.alter(table: "agent_coding_sessions") { t in
                t.add(column: "device_id", .text)  // nullable for existing rows
            }
            try db.create(indexOn: "agent_coding_sessions", columns: ["device_id"])
        }
    }
}
