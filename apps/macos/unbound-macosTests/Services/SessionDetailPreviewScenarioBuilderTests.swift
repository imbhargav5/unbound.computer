import Foundation
import XCTest

@testable import unbound_macos

#if DEBUG
final class SessionDetailPreviewScenarioBuilderTests: XCTestCase {
    func testFixtureShortIsNonZeroAndLessThanFixtureMax() throws {
        let loader = SessionDetailFixtureLoader(fixtureURL: fixtureURL())

        let fixtureMax = try SessionDetailPreviewScenarioBuilder.load(.fixtureMax, loader: loader)
        let fixtureShort = try SessionDetailPreviewScenarioBuilder.load(.fixtureShort, loader: loader)

        XCTAssertFalse(fixtureShort.parsedMessages.isEmpty)
        XCTAssertLessThan(fixtureShort.parsedMessages.count, fixtureMax.parsedMessages.count)
        XCTAssertEqual(fixtureShort.sourceMessageCount, fixtureShort.parsedMessages.count)
    }

    func testEmptyTimelineHasNoRenderableMessages() throws {
        let loader = SessionDetailFixtureLoader(fixtureURL: fixtureURL())

        let emptyTimeline = try SessionDetailPreviewScenarioBuilder.load(.emptyTimeline, loader: loader)

        XCTAssertTrue(emptyTimeline.parsedMessages.isEmpty)
        XCTAssertGreaterThan(emptyTimeline.sourceMessageCount, 0)
    }

    func testTextHeavySyntheticContainsTextContent() throws {
        let textHeavy = try SessionDetailPreviewScenarioBuilder.load(.textHeavySynthetic)

        let hasText = textHeavy.parsedMessages.contains { message in
            message.content.contains { content in
                if case .text(let textContent) = content {
                    return !textContent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return false
            }
        }

        XCTAssertTrue(hasText)
    }

    func testToolHeavySyntheticContainsToolLikeContent() throws {
        let toolHeavy = try SessionDetailPreviewScenarioBuilder.load(.toolHeavySynthetic)

        let hasToolLikeContent = toolHeavy.parsedMessages.contains { message in
            message.content.contains { content in
                switch content {
                case .toolUse, .subAgentActivity:
                    return true
                default:
                    return false
                }
            }
        }

        XCTAssertTrue(hasToolLikeContent)
    }

    func testStatusVariantsIncludeArchivedAndError() throws {
        let loader = SessionDetailFixtureLoader(fixtureURL: fixtureURL())
        let variants = try SessionDetailPreviewScenarioBuilder.loadStatusVariants(loader: loader)

        XCTAssertEqual(variants.archived.session.status, .archived)
        XCTAssertEqual(variants.error.session.status, .error)
        XCTAssertFalse(variants.archived.parsedMessages.isEmpty)
        XCTAssertFalse(variants.error.parsedMessages.isEmpty)
    }

    private func fixtureURL() -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SessionDetailPreviewScenarioBuilderTests.swift
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // unbound-macosTests
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // apps

        return repositoryRoot
            .appendingPathComponent("apps/macos/unbound-macos/Resources/PreviewFixtures/session-detail-max-messages.json")
    }
}
#endif
