//
//  SessionRepositoryTests.swift
//  unbound-macosTests
//
//  Session model behavior tests for daemon-backed persistence.
//

import Foundation
import XCTest
@testable import unbound_macos

final class SessionRepositoryTests: XCTestCase {
    func testSessionDisplayTitleFallsBackWhenEmpty() {
        let session = Session(
            repositoryId: UUID(),
            title: ""
        )
        XCTAssertEqual(session.displayTitle, "New conversation")
    }

    func testSessionWorkingDirectoryReturnsWorktreePath() {
        let session = Session(
            repositoryId: UUID(),
            isWorktree: true,
            worktreePath: "/tmp/my-worktree"
        )
        XCTAssertEqual(session.workingDirectory, "/tmp/my-worktree")
    }

    func testSessionWorktreeExistsTracksDirectoryLifecycle() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("worktree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )

        let session = Session(
            repositoryId: UUID(),
            isWorktree: true,
            worktreePath: tempDirectory.path
        )
        XCTAssertTrue(session.worktreeExists)

        try FileManager.default.removeItem(at: tempDirectory)
        XCTAssertFalse(session.worktreeExists)
    }

    func testDaemonSessionInvalidIdsReturnNil() {
        let daemonSession = DaemonSession(
            id: "bad-session-id",
            repositoryId: "bad-repo-id",
            title: "Broken",
            claudeSessionId: nil,
            status: "active",
            isWorktree: false,
            worktreePath: nil,
            createdAt: "2026-02-14T10:00:00.000Z",
            lastAccessedAt: "2026-02-14T10:00:00.000Z"
        )

        XCTAssertNil(daemonSession.toSession())
    }

    func testDaemonSessionUnknownStatusFallsBackToActive() {
        let repositoryID = UUID().uuidString.lowercased()
        let daemonSession = DaemonSession(
            id: UUID().uuidString.lowercased(),
            repositoryId: repositoryID,
            title: "Unknown status",
            claudeSessionId: nil,
            status: "not-real-status",
            isWorktree: nil,
            worktreePath: nil,
            createdAt: "2026-02-14T10:00:00.000Z",
            lastAccessedAt: "2026-02-14T10:00:00.000Z"
        )

        XCTAssertEqual(daemonSession.toSession()?.status, .active)
        XCTAssertEqual(daemonSession.toSession()?.isWorktree, false)
    }
}
