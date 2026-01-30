//
//  DatabaseService.swift
//  unbound-ios
//
//  Main database service using GRDB.swift for SQLite persistence.
//

import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "com.unbound.ios", category: "DatabaseService")

/// Database errors
enum DatabaseError: Error, LocalizedError {
    case notInitialized
    case migrationFailed(String)
    case encryptionKeyNotAvailable
    case recordNotFound
    case invalidData(String)
    case directoryCreationFailed

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database has not been initialized"
        case .migrationFailed(let reason):
            return "Database migration failed: \(reason)"
        case .encryptionKeyNotAvailable:
            return "Encryption key is not available"
        case .recordNotFound:
            return "Record not found"
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .directoryCreationFailed:
            return "Failed to create database directory"
        }
    }
}

/// Main database service - singleton
/// Must be initialized before app can proceed. Migration failures are fatal.
final class DatabaseService {
    static let shared = DatabaseService()

    private var dbPool: DatabasePool?
    private let fileManager = FileManager.default

    /// Database file URL (in Library/Application Support)
    private var databaseURL: URL {
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let appSupportURL = libraryURL.appendingPathComponent("Application Support", isDirectory: true)
        return appSupportURL.appendingPathComponent("unbound.sqlite")
    }

    /// Uploads base directory
    var uploadsDirectory: URL {
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryURL.appendingPathComponent("Application Support/uploads", isDirectory: true)
    }

    /// App support directory
    var appSupportDirectory: URL {
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryURL.appendingPathComponent("Application Support", isDirectory: true)
    }

    private init() {}

    // MARK: - Initialization

    /// Initialize the database. This MUST succeed or the app cannot start.
    /// - Throws: DatabaseError if initialization or migration fails
    func initialize() throws {
        logger.info("Database initialization started")
        logger.info("Database path: \(self.databaseURL.path)")

        // Ensure directory exists
        let directory = databaseURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create database directory: \(error.localizedDescription)")
                throw DatabaseError.directoryCreationFailed
            }
        }

        // Create database pool with configuration
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Use WAL mode for better concurrency
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        do {
            dbPool = try DatabasePool(path: databaseURL.path, configuration: config)
        } catch {
            logger.error("Failed to open database: \(error.localizedDescription)")
            throw DatabaseError.migrationFailed("Failed to open database: \(error.localizedDescription)")
        }

        // Run migrations - this MUST succeed
        try runMigrations()

        // Ensure upload directories exist
        try ensureUploadDirectoriesExist()

        logger.info("Database initialization completed")
    }

    /// Initialize the database asynchronously with progress updates
    func initializeAsync(progress: @escaping (String, Double) -> Void) async throws {
        progress("Initializing database...", 0.5)
        try initialize()
        progress("Database ready", 1.0)
    }

    /// Check if database is initialized
    var isInitialized: Bool {
        dbPool != nil
    }

    /// Get database pool (throws if not initialized)
    func getDatabase() throws -> DatabasePool {
        guard let db = dbPool else {
            throw DatabaseError.notInitialized
        }
        return db
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        guard let db = dbPool else {
            throw DatabaseError.notInitialized
        }

        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif

        // Register all migrations
        DatabaseMigrations.registerMigrations(&migrator)

        // Run migrations - failure is fatal
        do {
            try migrator.migrate(db)
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
            throw DatabaseError.migrationFailed(error.localizedDescription)
        }
    }

    // MARK: - Upload Directories

    private func ensureUploadDirectoriesExist() throws {
        let directories = [
            uploadsDirectory.appendingPathComponent("images"),
            uploadsDirectory.appendingPathComponent("text"),
            uploadsDirectory.appendingPathComponent("other")
        ]

        for dir in directories {
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Repository Access

    lazy var repositories: RepositoryRepository = {
        RepositoryRepository(databaseService: self)
    }()

    lazy var sessions: SessionRepository = {
        SessionRepository(databaseService: self)
    }()

    lazy var chatTabs: ChatTabRepository = {
        ChatTabRepository(databaseService: self)
    }()

    lazy var messages: MessageRepository = {
        MessageRepository(
            databaseService: self,
            encryptionService: MessageEncryptionService.shared
        )
    }()

    lazy var attachments: AttachmentRepository = {
        AttachmentRepository(databaseService: self)
    }()

    lazy var settings: SettingsRepository = {
        SettingsRepository(databaseService: self)
    }()

    // MARK: - Utility

    /// Get the database file path (for debugging)
    var databasePath: String {
        databaseURL.path
    }

    /// Check if database file exists
    var databaseFileExists: Bool {
        fileManager.fileExists(atPath: databaseURL.path)
    }
}
