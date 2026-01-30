//
//  DatabaseServiceTests.swift
//  unbound-macosTests
//
//  Unit tests for DatabaseService and database operations.
//

import XCTest
@testable import unbound_macos

final class DatabaseServiceTests: XCTestCase {

    var databaseService: DatabaseService!

    override func setUpWithError() throws {
        // Use the shared instance - in real tests you'd use a test database
        databaseService = DatabaseService.shared
    }

    override func tearDownWithError() throws {
        databaseService = nil
    }

    // MARK: - Initialization Tests

    func testDatabaseInitialization() throws {
        // Database should already be initialized by AppInitializer
        XCTAssertTrue(databaseService.isInitialized, "Database should be initialized")
        XCTAssertTrue(databaseService.databaseFileExists, "Database file should exist")
    }

    func testDatabasePathIsCorrect() {
        let path = databaseService.databasePath
        XCTAssertTrue(path.contains("com.unbound.macos"), "Database path should contain bundle ID")
        XCTAssertTrue(path.hasSuffix("unbound.sqlite"), "Database file should be named unbound.sqlite")
    }

    func testUploadsDirectoryExists() {
        let uploadsDir = databaseService.uploadsDirectory
        XCTAssertTrue(FileManager.default.fileExists(atPath: uploadsDir.path), "Uploads directory should exist")

        // Check subdirectories
        let imagesDir = uploadsDir.appendingPathComponent("images")
        let textDir = uploadsDir.appendingPathComponent("text")
        let otherDir = uploadsDir.appendingPathComponent("other")

        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesDir.path), "Images subdirectory should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: textDir.path), "Text subdirectory should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherDir.path), "Other subdirectory should exist")
    }
}
