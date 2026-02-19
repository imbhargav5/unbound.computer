//
//  AppStateSessionOrderingTests.swift
//  unbound-macosTests
//
//  Regression tests for recency-first ordering in repository session lists.
//

import Foundation
import XCTest
@testable import unbound_macos

final class AppStateSessionOrderingTests: XCTestCase {
    @MainActor
    func testSessionsForRepositorySortsByLastAccessedDescending() {
        let repositoryId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let base = Date(timeIntervalSince1970: 2_000)

        let oldest = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            repositoryId: repositoryId,
            title: "oldest",
            createdAt: base.addingTimeInterval(-500),
            lastAccessed: base.addingTimeInterval(-300)
        )
        let middle = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            repositoryId: repositoryId,
            title: "middle",
            createdAt: base.addingTimeInterval(-400),
            lastAccessed: base.addingTimeInterval(-100)
        )
        let newest = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            repositoryId: repositoryId,
            title: "newest",
            createdAt: base.addingTimeInterval(-50),
            lastAccessed: base
        )

        let appState = makeAppState(repositoryId: repositoryId, sessions: [middle, oldest, newest])
        let ordered = appState.sessionsForRepository(repositoryId)

        XCTAssertEqual(ordered.map(\.id), [newest.id, middle.id, oldest.id])
    }

    @MainActor
    func testSessionsForRepositoryUsesCreatedAtWhenLastAccessedMatches() {
        let repositoryId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let sharedLastAccessed = Date(timeIntervalSince1970: 3_000)

        let olderCreated = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            repositoryId: repositoryId,
            title: "older",
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastAccessed: sharedLastAccessed
        )
        let newerCreated = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            repositoryId: repositoryId,
            title: "newer",
            createdAt: Date(timeIntervalSince1970: 2_000),
            lastAccessed: sharedLastAccessed
        )

        let appState = makeAppState(repositoryId: repositoryId, sessions: [olderCreated, newerCreated])
        let ordered = appState.sessionsForRepository(repositoryId)

        XCTAssertEqual(ordered.map(\.id), [newerCreated.id, olderCreated.id])
    }

    @MainActor
    func testSessionsForRepositoryUsesUUIDTieBreakerWhenTimestampsMatch() {
        let repositoryId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let sharedCreated = Date(timeIntervalSince1970: 1_000)
        let sharedLastAccessed = Date(timeIntervalSince1970: 2_000)

        let lowerId = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            repositoryId: repositoryId,
            title: "lower-id",
            createdAt: sharedCreated,
            lastAccessed: sharedLastAccessed
        )
        let higherId = Session(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            repositoryId: repositoryId,
            title: "higher-id",
            createdAt: sharedCreated,
            lastAccessed: sharedLastAccessed
        )

        let appState = makeAppState(repositoryId: repositoryId, sessions: [lowerId, higherId])
        let ordered = appState.sessionsForRepository(repositoryId)

        XCTAssertEqual(ordered.map(\.id), [higherId.id, lowerId.id])
    }

    @MainActor
    private func makeAppState(repositoryId: UUID, sessions: [Session]) -> AppState {
        let appState = AppState()
        let repository = Repository(id: repositoryId, path: "/tmp/repo")

        appState.configureForPreview(
            repositories: [repository],
            sessions: [repositoryId: sessions],
            selectedRepositoryId: repositoryId
        )

        return appState
    }
}
