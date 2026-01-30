//
//  RepositoryRepository.swift
//  unbound-ios
//
//  Database repository for git repositories.
//

import Foundation
import GRDB

final class RepositoryRepository {
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    // MARK: - CRUD Operations

    /// Fetch all repositories ordered by last accessed
    func fetchAll() async throws -> [RepositoryRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try RepositoryRecord
                .order(Column("last_accessed_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch a single repository by ID
    func fetch(id: UUID) async throws -> RepositoryRecord? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try RepositoryRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
    }

    /// Fetch a repository by path
    func fetch(path: String) async throws -> RepositoryRecord? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try RepositoryRecord
                .filter(Column("path") == path)
                .fetchOne(db)
        }
    }

    /// Insert a new repository
    func insert(_ record: RepositoryRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.insert(db)
        }
    }

    /// Update an existing repository
    func update(_ record: RepositoryRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.update(db)
        }
    }

    /// Upsert a repository (insert or update)
    func upsert(_ record: RepositoryRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.save(db)
        }
    }

    /// Delete a repository by ID
    func delete(id: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try RepositoryRecord
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
    }

    /// Update last accessed time
    func updateLastAccessed(id: UUID) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE repositories
                    SET last_accessed_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), Date(), id.uuidString]
            )
        }
    }

    /// Check if a repository exists by path
    func exists(path: String) async throws -> Bool {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try RepositoryRecord
                .filter(Column("path") == path)
                .fetchCount(db) > 0
        }
    }

    /// Get total count of repositories
    func count() async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try RepositoryRecord.fetchCount(db)
        }
    }
}
