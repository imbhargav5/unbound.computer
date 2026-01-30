//
//  MessageRepository.swift
//  unbound-ios
//
//  Database repository for encrypted chat messages.
//  Messages are encrypted at rest using ChaCha20-Poly1305.
//

import Foundation
import GRDB

final class MessageRepository {
    private let databaseService: DatabaseService
    private let encryptionService: MessageEncryptionService

    init(databaseService: DatabaseService, encryptionService: MessageEncryptionService) {
        self.databaseService = databaseService
        self.encryptionService = encryptionService
    }

    // MARK: - Fetch Operations

    /// Fetch all messages for a chat tab, decrypted
    func fetch(chatTabId: UUID) async throws -> [(id: UUID, role: MessageRole, content: [MessageContent], timestamp: Date, isStreaming: Bool)] {
        let db = try databaseService.getDatabase()
        let records = try await db.read { db in
            try MessageRecord
                .filter(Column("chat_tab_id") == chatTabId.uuidString)
                .order(Column("sequence_number").asc)
                .fetchAll(db)
        }

        // Decrypt each message
        return try records.map { record in
            let content = try encryptionService.decrypt(
                ciphertext: record.contentEncrypted,
                nonce: record.contentNonce
            )
            return (
                id: UUID(uuidString: record.id) ?? UUID(),
                role: MessageRole(rawValue: record.role) ?? .user,
                content: content,
                timestamp: record.timestamp,
                isStreaming: record.isStreaming
            )
        }
    }

    /// Fetch a single message by ID (returns record without decryption)
    func fetchRecord(id: UUID) async throws -> MessageRecord? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try MessageRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
    }

    // MARK: - Insert Operations

    /// Insert a new message (encrypts content automatically)
    func insert(
        id: UUID,
        chatTabId: UUID,
        role: MessageRole,
        content: [MessageContent],
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        sequenceNumber: Int
    ) async throws {
        let (ciphertext, nonce) = try encryptionService.encrypt(content)

        let record = MessageRecord(
            id: id.uuidString,
            chatTabId: chatTabId.uuidString,
            role: role.rawValue,
            contentEncrypted: ciphertext,
            contentNonce: nonce,
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

    /// Insert multiple messages for a chat tab
    func insertAll(
        _ messages: [(id: UUID, role: MessageRole, content: [MessageContent], timestamp: Date, isStreaming: Bool)],
        chatTabId: UUID
    ) async throws {
        let db = try databaseService.getDatabase()

        // Encrypt all messages
        var records: [MessageRecord] = []
        for (index, message) in messages.enumerated() {
            let (ciphertext, nonce) = try encryptionService.encrypt(message.content)
            records.append(MessageRecord(
                id: message.id.uuidString,
                chatTabId: chatTabId.uuidString,
                role: message.role.rawValue,
                contentEncrypted: ciphertext,
                contentNonce: nonce,
                timestamp: message.timestamp,
                isStreaming: message.isStreaming,
                sequenceNumber: index,
                createdAt: Date()
            ))
        }

        try await db.write { db in
            for var record in records {
                try record.insert(db)
            }
        }
    }

    // MARK: - Update Operations

    /// Update message content (re-encrypts)
    func updateContent(id: UUID, content: [MessageContent]) async throws {
        let (ciphertext, nonce) = try encryptionService.encrypt(content)

        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE worktree_messages
                    SET content_encrypted = ?, content_nonce = ?
                    WHERE id = ?
                    """,
                arguments: [ciphertext, nonce, id.uuidString]
            )
        }
    }

    /// Update streaming status
    func updateStreaming(id: UUID, isStreaming: Bool) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE worktree_messages
                    SET is_streaming = ?
                    WHERE id = ?
                    """,
                arguments: [isStreaming, id.uuidString]
            )
        }
    }

    // MARK: - Delete Operations

    /// Delete a message by ID
    func delete(id: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try MessageRecord
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
    }

    /// Delete all messages for a chat tab
    func deleteAll(chatTabId: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try MessageRecord
                .filter(Column("chat_tab_id") == chatTabId.uuidString)
                .deleteAll(db)
        }
    }

    // MARK: - Utility

    /// Get count of messages in a chat tab
    func count(chatTabId: UUID) async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try MessageRecord
                .filter(Column("chat_tab_id") == chatTabId.uuidString)
                .fetchCount(db)
        }
    }

    /// Get the next sequence number for a chat tab
    func getNextSequenceNumber(chatTabId: UUID) async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            let maxSequence = try Int.fetchOne(
                db,
                sql: """
                    SELECT MAX(sequence_number) FROM worktree_messages
                    WHERE chat_tab_id = ?
                    """,
                arguments: [chatTabId.uuidString]
            )
            return (maxSequence ?? -1) + 1
        }
    }
}
