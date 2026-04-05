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

    func testSessionDisplayAgentNameFallsBackWhenMissing() {
        let session = Session(repositoryId: UUID(), agentName: nil)
        XCTAssertEqual(session.displayAgentName, "Agent")

        let namedSession = Session(repositoryId: UUID(), agentName: "Ops Agent")
        XCTAssertEqual(namedSession.displayAgentName, "Ops Agent")
    }

    func testSessionDisplayIssueTitlePrefersTitleThenId() {
        let issueTitled = Session(
            repositoryId: UUID(),
            issueId: "ENG-123",
            issueTitle: "Fix integration flow"
        )
        XCTAssertEqual(issueTitled.displayIssueTitle, "Fix integration flow")

        let issueIdOnly = Session(repositoryId: UUID(), issueId: "ENG-456")
        XCTAssertEqual(issueIdOnly.displayIssueTitle, "ENG-456")
    }

    func testDaemonSessionInvalidIdsReturnNil() {
        let daemonSession = DaemonSession(
            id: "bad-session-id",
            repositoryId: "bad-repo-id",
            title: "Broken",
            agentId: nil,
            agentName: nil,
            issueId: nil,
            issueTitle: nil,
            issueURL: nil,
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
            agentId: "agent-123",
            agentName: "Debug Agent",
            issueId: "ENG-123",
            issueTitle: "Fix integration flow",
            issueURL: "https://example.com/issues/ENG-123",
            claudeSessionId: nil,
            status: "not-real-status",
            isWorktree: nil,
            worktreePath: nil,
            createdAt: "2026-02-14T10:00:00.000Z",
            lastAccessedAt: "2026-02-14T10:00:00.000Z"
        )

        XCTAssertEqual(daemonSession.toSession()?.status, .active)
        XCTAssertEqual(daemonSession.toSession()?.isWorktree, false)
        XCTAssertEqual(daemonSession.toSession()?.agentId, "agent-123")
        XCTAssertEqual(daemonSession.toSession()?.agentName, "Debug Agent")
        XCTAssertEqual(daemonSession.toSession()?.issueId, "ENG-123")
        XCTAssertEqual(daemonSession.toSession()?.issueTitle, "Fix integration flow")
        XCTAssertEqual(daemonSession.toSession()?.issueURL, "https://example.com/issues/ENG-123")
    }
}
