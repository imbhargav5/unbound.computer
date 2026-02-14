//
//  DatabaseServiceTests.swift
//  unbound-macosTests
//
//  Regression tests for daemon-backed repository/session data conversion.
//

import XCTest
@testable import unbound_macos

final class DatabaseServiceTests: XCTestCase {
    func testDaemonRepositoryConvertsToRepository() {
        let daemonRepository = DaemonRepository(
            id: UUID().uuidString.lowercased(),
            name: "unbound.computer",
            path: "/tmp/unbound.computer",
            isGitRepository: true,
            sessionsPath: "/tmp/unbound-sessions",
            defaultBranch: "main",
            defaultRemote: "origin",
            lastAccessedAt: "2026-02-14T10:30:15.123Z"
        )

        let repository = daemonRepository.toRepository()
        XCTAssertNotNil(repository)
        XCTAssertEqual(repository?.name, "unbound.computer")
        XCTAssertEqual(repository?.path, "/tmp/unbound.computer")
        XCTAssertEqual(repository?.sessionsPath, "/tmp/unbound-sessions")
        XCTAssertEqual(repository?.defaultBranch, "main")
        XCTAssertEqual(repository?.defaultRemote, "origin")
        XCTAssertEqual(repository?.isGitRepository, true)
    }

    func testDaemonRepositoryInvalidUUIDReturnsNil() {
        let daemonRepository = DaemonRepository(
            id: "not-a-uuid",
            name: "invalid",
            path: "/tmp/invalid",
            isGitRepository: true,
            sessionsPath: nil,
            defaultBranch: nil,
            defaultRemote: nil,
            lastAccessedAt: "2026-02-14T10:30:15.123Z"
        )

        XCTAssertNil(daemonRepository.toRepository())
    }

    func testDaemonSessionConvertsToSession() {
        let repositoryID = UUID()
        let daemonSession = DaemonSession(
            id: UUID().uuidString.lowercased(),
            repositoryId: repositoryID.uuidString.lowercased(),
            title: "Fix integration",
            claudeSessionId: "claude-session-1",
            status: "active",
            isWorktree: true,
            worktreePath: "/tmp/worktree",
            createdAt: "2026-02-14T10:00:00.000Z",
            lastAccessedAt: "2026-02-14T10:30:00.000Z"
        )

        let session = daemonSession.toSession()
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.repositoryId, repositoryID)
        XCTAssertEqual(session?.title, "Fix integration")
        XCTAssertEqual(session?.status, .active)
        XCTAssertEqual(session?.isWorktree, true)
        XCTAssertEqual(session?.worktreePath, "/tmp/worktree")
    }
}
