import Foundation
import XCTest

@testable import unbound_ios

final class SessionDetailFixtureMessageLoaderTests: XCTestCase {
    func testLoadFixtureDecodesCommittedMaxSessionFixture() throws {
        let loader = SessionDetailFixtureMessageLoader(fixtureURL: fixtureURL())

        let fixture = try loader.loadFixture()

        XCTAssertEqual(fixture.metadata.selectedMessageCount, fixture.messages.count)
        XCTAssertFalse(fixture.messages.isEmpty)
        XCTAssertFalse(fixture.session.id.isEmpty)
    }

    func testLoadMessagesMapsCommittedFixtureIntoRenderableTimeline() async throws {
        let loader = SessionDetailFixtureMessageLoader(fixtureURL: fixtureURL())
        let fixture = try loader.loadFixture()

        let result = try await loader.loadMessages(sessionId: UUID())

        XCTAssertEqual(result.decryptedMessageCount, fixture.messages.count)
        XCTAssertFalse(result.messages.isEmpty)
        XCTAssertTrue(result.messages.contains { message in
            guard let blocks = message.parsedContent else { return false }
            return blocks.contains { block in
                if case .subAgentActivity = block {
                    return true
                }
                return false
            }
        })
    }

    private func fixtureURL() -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return repositoryRoot
            .appendingPathComponent("apps/ios/unbound-ios/Resources/PreviewFixtures/session-detail-max-messages.json")
    }
}
