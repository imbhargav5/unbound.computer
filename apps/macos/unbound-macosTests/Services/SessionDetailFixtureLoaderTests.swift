import Foundation
import XCTest

@testable import unbound_macos

final class SessionDetailFixtureLoaderTests: XCTestCase {
    func testLoadFixtureDecodesCommittedFixture() throws {
        let loader = SessionDetailFixtureLoader(fixtureURL: fixtureURL())

        let fixture = try loader.loadFixture()

        XCTAssertEqual(fixture.metadata.selectedMessageCount, fixture.messages.count)
        XCTAssertFalse(fixture.messages.isEmpty)
        XCTAssertFalse(fixture.session.id.isEmpty)
        XCTAssertFalse(fixture.session.title.isEmpty)
    }

    func testLoadParsedMessagesProducesRenderableStructuredTimeline() throws {
        let loader = SessionDetailFixtureLoader(fixtureURL: fixtureURL())

        let parsedMessages = try loader.loadParsedMessages()

        XCTAssertFalse(parsedMessages.isEmpty)

        let hasText = parsedMessages.contains { message in
            message.content.contains { content in
                if case .text(let textContent) = content {
                    return !textContent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return false
            }
        }

        let hasStructuredToolContent = parsedMessages.contains { message in
            message.content.contains { content in
                switch content {
                case .toolUse, .subAgentActivity:
                    return true
                default:
                    return false
                }
            }
        }

        XCTAssertTrue(hasText)
        XCTAssertTrue(hasStructuredToolContent)
    }

    func testMapSessionMapsStatusAndFallsBackForUnknownStatus() {
        let repositoryId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let createdAt = Date(timeIntervalSince1970: 1)
        let lastAccessedAt = Date(timeIntervalSince1970: 2)

        let archivedFixtureSession = SessionDetailFixture.Session(
            id: "10000000-0000-0000-0000-000000000001",
            title: "Archived Session",
            status: "archived",
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt
        )
        let archivedSession = SessionDetailFixtureLoader.mapSession(
            archivedFixtureSession,
            repositoryId: repositoryId
        )

        XCTAssertEqual(archivedSession.id.uuidString.lowercased(), archivedFixtureSession.id)
        XCTAssertEqual(archivedSession.title, archivedFixtureSession.title)
        XCTAssertEqual(archivedSession.status, .archived)

        let unknownFixtureSession = SessionDetailFixture.Session(
            id: "10000000-0000-0000-0000-000000000002",
            title: "Unknown Status Session",
            status: "mystery-status",
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt
        )
        let fallbackSession = SessionDetailFixtureLoader.mapSession(
            unknownFixtureSession,
            repositoryId: repositoryId
        )

        XCTAssertEqual(fallbackSession.status, .active)
    }

    private func fixtureURL() -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SessionDetailFixtureLoaderTests.swift
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // unbound-macosTests
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // apps

        return repositoryRoot
            .appendingPathComponent("apps/macos/unbound-macos/Resources/PreviewFixtures/session-detail-max-messages.json")
    }
}
