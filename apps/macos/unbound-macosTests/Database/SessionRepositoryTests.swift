//
//  SessionRepositoryTests.swift
//  unbound-macosTests
//
//  Unit tests for SessionRepository database operations.
//

import XCTest
@testable import unbound_macos

final class SessionRepositoryTests: XCTestCase {

    var sessionRepo: SessionRepository!

    override func setUpWithError() throws {
        sessionRepo = DatabaseService.shared.sessions
    }

    override func tearDownWithError() throws {
        sessionRepo = nil
    }

    // MARK: - CRUD Tests

    func testInsertAndFetchSession() async throws {
        let testSession = Session(
            id: UUID(),
            name: "test-session-\(UUID().uuidString.prefix(8))",
            repositoryId: nil,
            worktreePath: "/tmp/worktree",
            createdAt: Date(),
            lastAccessed: Date(),
            status: .active
        )

        // Insert
        try await sessionRepo.insert(testSession)

        // Fetch
        let fetched = try await sessionRepo.fetch(id: testSession.id)
        XCTAssertNotNil(fetched, "Session should be fetchable after insert")
        XCTAssertEqual(fetched?.name, testSession.name, "Session name should match")
        XCTAssertEqual(fetched?.status, .active, "Session status should be active")

        // Cleanup
        try await sessionRepo.delete(id: testSession.id)
    }

    func testFetchActiveSessions() async throws {
        let activeSession = Session(
            name: "active-session-\(UUID().uuidString.prefix(8))",
            status: .active
        )
        let archivedSession = Session(
            name: "archived-session-\(UUID().uuidString.prefix(8))",
            status: .archived
        )

        try await sessionRepo.insert(activeSession)
        try await sessionRepo.insert(archivedSession)

        let activeSessions = try await sessionRepo.fetchActive()

        XCTAssertTrue(activeSessions.contains { $0.id == activeSession.id }, "Active session should be in active list")
        XCTAssertFalse(activeSessions.contains { $0.id == archivedSession.id }, "Archived session should not be in active list")

        // Cleanup
        try await sessionRepo.delete(id: activeSession.id)
        try await sessionRepo.delete(id: archivedSession.id)
    }

    func testUpdateSessionStatus() async throws {
        let testSession = Session(
            name: "status-test-\(UUID().uuidString.prefix(8))",
            status: .active
        )

        try await sessionRepo.insert(testSession)

        // Update status to archived
        try await sessionRepo.updateStatus(id: testSession.id, status: .archived)

        let fetched = try await sessionRepo.fetch(id: testSession.id)
        XCTAssertEqual(fetched?.status, .archived, "Session status should be archived")

        // Cleanup
        try await sessionRepo.delete(id: testSession.id)
    }

    func testArchiveSession() async throws {
        let testSession = Session(
            name: "archive-test-\(UUID().uuidString.prefix(8))",
            status: .active
        )

        try await sessionRepo.insert(testSession)

        // Archive
        try await sessionRepo.archive(id: testSession.id)

        let fetched = try await sessionRepo.fetch(id: testSession.id)
        XCTAssertEqual(fetched?.status, .archived, "Session should be archived")

        // Cleanup
        try await sessionRepo.delete(id: testSession.id)
    }

    func testCountSessions() async throws {
        let initialCount = try await sessionRepo.count()

        let testSession = Session(
            name: "count-test-\(UUID().uuidString.prefix(8))",
            status: .active
        )
        try await sessionRepo.insert(testSession)

        let afterInsertCount = try await sessionRepo.count()
        XCTAssertEqual(afterInsertCount, initialCount + 1, "Count should increase by 1")

        // Cleanup
        try await sessionRepo.delete(id: testSession.id)
    }
}
