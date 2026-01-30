//
//  RepositoryRepositoryTests.swift
//  unbound-macosTests
//
//  Unit tests for RepositoryRepository database operations.
//

import XCTest
@testable import unbound_macos

final class RepositoryRepositoryTests: XCTestCase {

    var repositoryRepo: RepositoryRepository!

    override func setUpWithError() throws {
        repositoryRepo = DatabaseService.shared.repositories
    }

    override func tearDownWithError() throws {
        repositoryRepo = nil
    }

    // MARK: - CRUD Tests

    func testInsertAndFetchRepository() async throws {
        let testRepo = Repository(
            id: UUID(),
            path: "/tmp/test-repo-\(UUID().uuidString)",
            name: "Test Repository",
            lastAccessed: Date(),
            addedAt: Date(),
            isGitRepository: true,
            sessionsPath: "/tmp/sessions",
            defaultBranch: "main",
            defaultRemote: "origin"
        )

        // Insert
        try await repositoryRepo.insert(testRepo)

        // Fetch
        let fetched = try await repositoryRepo.fetch(id: testRepo.id)
        XCTAssertNotNil(fetched, "Repository should be fetchable after insert")
        XCTAssertEqual(fetched?.name, testRepo.name, "Repository name should match")
        XCTAssertEqual(fetched?.path, testRepo.path, "Repository path should match")
        XCTAssertEqual(fetched?.isGitRepository, testRepo.isGitRepository, "isGitRepository should match")

        // Cleanup
        try await repositoryRepo.delete(id: testRepo.id)
    }

    func testFetchByPath() async throws {
        let uniquePath = "/tmp/test-repo-path-\(UUID().uuidString)"
        let testRepo = Repository(
            path: uniquePath,
            name: "Path Test Repository",
            isGitRepository: true
        )

        try await repositoryRepo.insert(testRepo)

        let fetched = try await repositoryRepo.fetch(path: uniquePath)
        XCTAssertNotNil(fetched, "Repository should be fetchable by path")
        XCTAssertEqual(fetched?.id, testRepo.id, "Repository ID should match")

        // Cleanup
        try await repositoryRepo.delete(id: testRepo.id)
    }

    func testUpdateRepository() async throws {
        let testRepo = Repository(
            path: "/tmp/test-repo-update-\(UUID().uuidString)",
            name: "Original Name",
            isGitRepository: true
        )

        try await repositoryRepo.insert(testRepo)

        // Update
        var updated = testRepo
        updated = Repository(
            id: testRepo.id,
            path: testRepo.path,
            name: "Updated Name",
            lastAccessed: Date(),
            addedAt: testRepo.addedAt,
            isGitRepository: testRepo.isGitRepository,
            sessionsPath: "/new/path",
            defaultBranch: "develop",
            defaultRemote: "upstream"
        )
        try await repositoryRepo.update(updated)

        // Verify
        let fetched = try await repositoryRepo.fetch(id: testRepo.id)
        XCTAssertEqual(fetched?.sessionsPath, "/new/path", "Sessions path should be updated")
        XCTAssertEqual(fetched?.defaultBranch, "develop", "Default branch should be updated")

        // Cleanup
        try await repositoryRepo.delete(id: testRepo.id)
    }

    func testDeleteRepository() async throws {
        let testRepo = Repository(
            path: "/tmp/test-repo-delete-\(UUID().uuidString)",
            name: "Delete Test",
            isGitRepository: false
        )

        try await repositoryRepo.insert(testRepo)

        // Verify it exists
        let beforeDelete = try await repositoryRepo.fetch(id: testRepo.id)
        XCTAssertNotNil(beforeDelete, "Repository should exist before delete")

        // Delete
        try await repositoryRepo.delete(id: testRepo.id)

        // Verify it's gone
        let afterDelete = try await repositoryRepo.fetch(id: testRepo.id)
        XCTAssertNil(afterDelete, "Repository should not exist after delete")
    }

    func testUpdateLastAccessed() async throws {
        let testRepo = Repository(
            path: "/tmp/test-repo-touch-\(UUID().uuidString)",
            name: "Touch Test",
            lastAccessed: Date(timeIntervalSince1970: 0), // Old date
            isGitRepository: true
        )

        try await repositoryRepo.insert(testRepo)

        let beforeTouch = try await repositoryRepo.fetch(id: testRepo.id)
        let oldAccessDate = beforeTouch?.lastAccessed

        // Wait a moment and update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        try await repositoryRepo.updateLastAccessed(id: testRepo.id)

        let afterTouch = try await repositoryRepo.fetch(id: testRepo.id)
        XCTAssertNotNil(afterTouch?.lastAccessed, "Last accessed should be set")
        XCTAssertGreaterThan(afterTouch!.lastAccessed, oldAccessDate!, "Last accessed should be updated")

        // Cleanup
        try await repositoryRepo.delete(id: testRepo.id)
    }

    func testExistsByPath() async throws {
        let uniquePath = "/tmp/test-repo-exists-\(UUID().uuidString)"
        let testRepo = Repository(
            path: uniquePath,
            name: "Exists Test",
            isGitRepository: true
        )

        // Should not exist before insert
        let beforeInsert = try await repositoryRepo.exists(path: uniquePath)
        XCTAssertFalse(beforeInsert, "Repository should not exist before insert")

        try await repositoryRepo.insert(testRepo)

        // Should exist after insert
        let afterInsert = try await repositoryRepo.exists(path: uniquePath)
        XCTAssertTrue(afterInsert, "Repository should exist after insert")

        // Cleanup
        try await repositoryRepo.delete(id: testRepo.id)
    }
}
