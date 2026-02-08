//
//  AppInitializer.swift
//  unbound-ios
//
//  Handles app initialization including database setup.
//  Device identity is initialized after authentication (user-scoped).
//  The app will not start if database initialization fails.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.unbound.ios", category: "AppInitializer")

/// Errors during app initialization
enum AppInitializationError: Error, LocalizedError {
    case databaseInitializationFailed(String)
    case encryptionKeyUnavailable

    var errorDescription: String? {
        switch self {
        case .databaseInitializationFailed(let reason):
            return "Failed to initialize database: \(reason)"
        case .encryptionKeyUnavailable:
            return "Encryption key is not available"
        }
    }
}

/// App initialization result
struct AppInitializationResult {
    let databaseInitialized: Bool
}

/// Handles app initialization - must be called before any other app services
/// Note: Device identity initialization happens after authentication in AuthService
final class AppInitializer {
    static let shared = AppInitializer()

    private let databaseService: DatabaseService

    private(set) var isInitialized = false
    private(set) var initializationError: Error?

    private init(
        databaseService: DatabaseService = .shared
    ) {
        self.databaseService = databaseService
    }

    // MARK: - Initialization

    /// Initialize the app - MUST succeed or app cannot start
    /// Call this at app launch before any other service initialization
    /// Note: Device identity is initialized after authentication, not here
    /// - Throws: AppInitializationError if initialization fails
    /// - Returns: Initialization result with details
    @discardableResult
    func initialize(recreateDatabase: Bool = false) throws -> AppInitializationResult {
        logger.info("Starting app initialization...")

        guard !isInitialized else {
            logger.info("Already initialized, skipping")
            return AppInitializationResult(
                databaseInitialized: true
            )
        }

        do {
            // Initialize database (creates schema, runs migrations)
            logger.info("Step 1/1: Initializing database...")
            try initializeDatabase(recreateDatabase: recreateDatabase)
            logger.info("Database initialized")

            isInitialized = true
            logger.info("App initialization completed successfully")

            return AppInitializationResult(
                databaseInitialized: true
            )
        } catch let error as DatabaseError {
            logger.error("Database error during initialization: \(error.localizedDescription)")
            initializationError = error
            throw AppInitializationError.databaseInitializationFailed(error.localizedDescription)
        } catch {
            logger.error("Unknown error during initialization: \(error.localizedDescription)")
            initializationError = error
            throw AppInitializationError.databaseInitializationFailed(error.localizedDescription)
        }
    }

    // MARK: - Async Initialization (Preferred)

    /// Initialize the app asynchronously - preferred method for SwiftUI apps
    /// This avoids blocking the main thread and provides better UX with loading states
    /// Note: Device identity is initialized after authentication, not here
    /// - Parameter progress: Optional callback for progress updates
    /// - Throws: AppInitializationError if initialization fails
    /// - Returns: Initialization result with details
    @discardableResult
    func initializeAsync(
        recreateDatabase: Bool = false,
        progress: ((String, Double) -> Void)? = nil
    ) async throws -> AppInitializationResult {
        logger.info("Starting async app initialization...")

        guard !isInitialized else {
            logger.info("Already initialized, skipping")
            return AppInitializationResult(
                databaseInitialized: true
            )
        }

        do {
            // Initialize database (creates schema, runs migrations)
            logger.info("Step 1/1: Initializing database...")
            progress?("Setting up database...", 0.5)
            try initializeDatabase(recreateDatabase: recreateDatabase)
            logger.info("Database initialized")

            isInitialized = true
            progress?("Ready!", 1.0)
            logger.info("Async app initialization completed successfully")

            return AppInitializationResult(
                databaseInitialized: true
            )
        } catch let error as DatabaseError {
            logger.error("Database error during async initialization: \(error.localizedDescription)")
            initializationError = error
            throw AppInitializationError.databaseInitializationFailed(error.localizedDescription)
        } catch {
            logger.error("Unknown error during async initialization: \(error.localizedDescription)")
            initializationError = error
            throw AppInitializationError.databaseInitializationFailed(error.localizedDescription)
        }
    }

    // MARK: - State

    /// Reset initialization state (for testing)
    func reset() {
        isInitialized = false
        initializationError = nil
    }

    // MARK: - Private

    private func initializeDatabase(recreateDatabase: Bool) throws {
        #if DEBUG
        if recreateDatabase || Config.recreateLocalDatabaseOnLaunch {
            logger.notice("Recreating local database before initialization")
            try databaseService.recreateLocalDatabase()
        }
        #endif

        try databaseService.initialize()
    }
}
