//
//  ChatTabRepository.swift
//  unbound-ios
//
//  Database repository for chat tabs.
//

import Foundation
import GRDB

final class ChatTabRepository {
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    // MARK: - CRUD Operations

    /// Fetch all chat tabs for a session
    func fetch(sessionId: UUID) async throws -> [ChatTabRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try ChatTabRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch a single chat tab by ID
    func fetch(id: UUID) async throws -> ChatTabRecord? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try ChatTabRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
    }

    /// Insert a new chat tab
    func insert(_ record: ChatTabRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.insert(db)
        }
    }

    /// Update an existing chat tab
    func update(_ record: ChatTabRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.update(db)
        }
    }

    /// Update chat tab title
    func updateTitle(id: UUID, title: String) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE chat_tabs
                    SET title = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [title, Date(), id.uuidString]
            )
        }
    }

    /// Update Claude session ID
    func updateClaudeSessionId(id: UUID, claudeSessionId: String?) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE chat_tabs
                    SET claude_session_id = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [claudeSessionId, Date(), id.uuidString]
            )
        }
    }

    /// Delete a chat tab by ID
    func delete(id: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try ChatTabRecord
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
    }

    /// Delete all chat tabs for a session
    func deleteAll(sessionId: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try ChatTabRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .deleteAll(db)
        }
    }

    /// Get count of chat tabs for a session
    func count(sessionId: UUID) async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try ChatTabRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .fetchCount(db)
        }
    }

    /// Get the session ID for a chat tab
    func getSessionId(chatTabId: UUID) async throws -> UUID? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            let record = try ChatTabRecord
                .filter(Column("id") == chatTabId.uuidString)
                .fetchOne(db)
            return record.flatMap { UUID(uuidString: $0.sessionId) }
        }
    }
}
