//
//  MigrationTests.swift
//  unbound-macosTests
//
//  Tests for database migration functionality.
//

import XCTest
@testable import unbound_macos

final class MigrationTests: XCTestCase {

    // MARK: - App Initialization Tests

    func testAppInitializerCompletes() {
        // AppInitializer should already be initialized by AppState
        XCTAssertTrue(AppInitializer.shared.isInitialized, "AppInitializer should be initialized")
        XCTAssertNil(AppInitializer.shared.initializationError, "There should be no initialization error")
    }

    func testDatabaseMigrationServiceCanBeCreated() {
        let migrationService = DatabaseMigrationService()
        XCTAssertNotNil(migrationService, "Migration service should be creatable")
    }

    // MARK: - Migration Check Tests

    func testMigrationCheckDoesNotCrash() {
        let migrationService = DatabaseMigrationService()

        // This should not throw
        let needsMigration = migrationService.needsMigration()

        // After initial migration, should not need migration again
        // (unless there are JSON files present)
        XCTAssertNotNil(needsMigration, "needsMigration should return a value")
    }

    // MARK: - Settings Migration Tests

    func testSettingsRepositoryWorks() async throws {
        let settingsRepo = DatabaseService.shared.settings

        // Test string setting
        let testKey = "test_setting_\(UUID().uuidString)"
        try await settingsRepo.setString(testKey, value: "test_value")

        let retrieved = try await settingsRepo.getString(testKey)
        XCTAssertEqual(retrieved, "test_value", "String setting should be retrievable")

        // Cleanup
        try await settingsRepo.delete(testKey)
    }

    func testSettingsRepositoryTypedValues() async throws {
        let settingsRepo = DatabaseService.shared.settings

        // Test int
        let intKey = "test_int_\(UUID().uuidString)"
        try await settingsRepo.setInt(intKey, value: 42)
        let intValue = try await settingsRepo.getInt(intKey)
        XCTAssertEqual(intValue, 42, "Int setting should match")

        // Test bool
        let boolKey = "test_bool_\(UUID().uuidString)"
        try await settingsRepo.setBool(boolKey, value: true)
        let boolValue = try await settingsRepo.getBool(boolKey)
        XCTAssertEqual(boolValue, true, "Bool setting should match")

        // Cleanup
        try await settingsRepo.delete(intKey)
        try await settingsRepo.delete(boolKey)
    }
}
