//
//  MessageRepository.swift
//  unbound-ios
//
//  Database repository for coding session messages.
//  Local iOS schema stores plaintext `content` to mirror macOS SQLite.
//

import Foundation
import GRDB

final class MessageRepository {
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    // MARK: - Fetch Operations

    /// Fetch all message records for a session ordered by sequence.
    func fetch(sessionId: UUID) async throws -> [MessageRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try MessageRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .order(Column("sequence_number").asc)
                .fetchAll(db)
        }
    }

    /// Fetch a single message by ID.
    func fetchRecord(id: UUID) async throws -> MessageRecord? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try MessageRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
    }

    // MARK: - Insert Operations

    /// Insert a new plaintext message record.
    func insert(
        id: UUID,
        sessionId: UUID,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        sequenceNumber: Int
    ) async throws {
        let record = MessageRecord(
            id: id.uuidString,
            sessionId: sessionId.uuidString,
            content: content,
            timestamp: timestamp,
            isStreaming: isStreaming,
            sequenceNumber: sequenceNumber,
            createdAt: Date()
        )

        let db = try databaseService.getDatabase()
        try await db.write { db in
            var mutableRecord = record
            try mutableRecord.insert(db)
        }
    }

    /// Insert multiple plaintext messages for a session.
    func insertAll(
        _ messages: [(id: UUID, content: String, timestamp: Date, isStreaming: Bool)],
        sessionId: UUID
    ) async throws {
        let db = try databaseService.getDatabase()

        let records: [MessageRecord] = messages.enumerated().map { index, message in
            MessageRecord(
                id: message.id.uuidString,
                sessionId: sessionId.uuidString,
                content: message.content,
                timestamp: message.timestamp,
                isStreaming: message.isStreaming,
                sequenceNumber: index,
                createdAt: Date()
            )
        }

        try await db.write { db in
            for var record in records {
                try record.insert(db)
            }
        }
    }

    // MARK: - Update Operations

    /// Update message content.
    func updateContent(id: UUID, content: String) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE agent_coding_session_messages
                    SET content = ?
                    WHERE id = ?
                    """,
                arguments: [content, id.uuidString]
            )
        }
    }

    /// Update streaming status.
    func updateStreaming(id: UUID, isStreaming: Bool) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE agent_coding_session_messages
                    SET is_streaming = ?
                    WHERE id = ?
                    """,
                arguments: [isStreaming, id.uuidString]
            )
        }
    }

    // MARK: - Delete Operations

    /// Delete a message by ID.
    func delete(id: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try MessageRecord
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
    }

    /// Delete all messages for a session.
    func deleteAll(sessionId: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try MessageRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .deleteAll(db)
        }
    }

    // MARK: - Utility

    /// Get count of messages in a session.
    func count(sessionId: UUID) async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try MessageRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .fetchCount(db)
        }
    }

    /// Get the next sequence number for a session.
    func getNextSequenceNumber(sessionId: UUID) async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            let maxSequence = try Int.fetchOne(
                db,
                sql: """
                    SELECT MAX(sequence_number) FROM agent_coding_session_messages
                    WHERE session_id = ?
                    """,
                arguments: [sessionId.uuidString]
            )
            return (maxSequence ?? -1) + 1
        }
    }
}
