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
    }
}
