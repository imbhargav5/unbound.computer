//
//  SessionRepository.swift
//  unbound-ios
//
//  Database repository for worktree sessions.
//

import Foundation
import GRDB

final class SessionRepository {
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    // MARK: - CRUD Operations

    /// Fetch all sessions ordered by last accessed
    func fetchAll() async throws -> [SessionRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try SessionRecord
                .order(Column("last_accessed_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch all active sessions
    func fetchActive() async throws -> [SessionRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try SessionRecord
                .filter(Column("status") == CodingSessionStatus.active.rawValue)
                .order(Column("last_accessed_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch sessions for a specific repository
    func fetch(repositoryId: UUID) async throws -> [SessionRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try SessionRecord
                .filter(Column("repository_id") == repositoryId.uuidString)
                .order(Column("last_accessed_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch a single session by ID
    func fetch(id: UUID) async throws -> SessionRecord? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try SessionRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
    }

    /// Insert a new session
    func insert(_ record: SessionRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.insert(db)
        }
    }

    /// Update an existing session
    func update(_ record: SessionRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.update(db)
        }
    }

    /// Upsert a session
    func upsert(_ record: SessionRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.save(db)
        }
    }

    /// Delete a session by ID
    func delete(id: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try SessionRecord
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
    }

    /// Update session status
    func updateStatus(id: UUID, status: CodingSessionStatus) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE agent_coding_sessions
                    SET status = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [status.rawValue, Date(), id.uuidString]
            )
        }
    }

    /// Update session title
    func updateTitle(id: UUID, title: String, updatedAt: Date) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE agent_coding_sessions
                    SET title = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [title, updatedAt, id.uuidString]
            )
        }
    }

    /// Update last accessed time
    func updateLastAccessed(id: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE agent_coding_sessions
                    SET last_accessed_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), Date(), id.uuidString]
            )
        }
    }

    /// End a session
    func end(id: UUID) async throws {
        try await updateStatus(id: id, status: .ended)
    }

    /// Get count of sessions
    func count() async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try SessionRecord.fetchCount(db)
        }
    }

    /// Get count of active sessions
    func countActive() async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try SessionRecord
                .filter(Column("status") == CodingSessionStatus.active.rawValue)
                .fetchCount(db)
        }
    }
}
