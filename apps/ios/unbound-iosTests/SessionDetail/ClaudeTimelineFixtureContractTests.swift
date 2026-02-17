import ClaudeConversationTimeline
import XCTest

final class ClaudeTimelineFixtureContractTests: XCTestCase {
    func testSharedClaudeFixturesParse() throws {
        let fixtureURL = try sharedFixtureURL()
        let data = try Data(contentsOf: fixtureURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])

        for fixtureCase in cases {
            let parser = ClaudeConversationTimelineParser()
            let events = fixtureCase["events"] as? [Any] ?? []

            for event in events {
                let eventData = try JSONSerialization.data(withJSONObject: event)
                let jsonString = try XCTUnwrap(String(data: eventData, encoding: .utf8))
                parser.ingest(rawJSON: jsonString)
            }

            let entries = parser.currentTimeline()
            let roles = Set(entries.map { $0.role.rawValue })
            let blockTypes = Set(entries.flatMap { entry in
                entry.blocks.map(blockTypeName)
            })

            let expectations = fixtureCase["expect"] as? [String: Any]
            let expectedRoles = expectations?["roles"] as? [String] ?? []
            let expectedBlocks = expectations?["blockTypes"] as? [String] ?? []

            for role in expectedRoles {
                XCTAssertTrue(roles.contains(role), "Expected role \(role) in fixture \(fixtureCase["id"] as? String ?? "unknown")")
            }

            for block in expectedBlocks {
                XCTAssertTrue(blockTypes.contains(block), "Expected block \(block) in fixture \(fixtureCase["id"] as? String ?? "unknown")")
            }
        }
    }

    private func sharedFixtureURL() throws -> URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        let baseURL = fileURL.deletingLastPathComponent()
        let fixturePath = baseURL
            .appendingPathComponent("../../../shared/ClaudeConversationTimeline/Fixtures/claude-parser-contract-fixtures.json")
            .standardizedFileURL
        if !FileManager.default.fileExists(atPath: fixturePath.path) {
            throw XCTSkip("Shared fixture not found at \(fixturePath.path)")
        }
        return fixturePath
    }

    private func blockTypeName(_ block: ClaudeConversationBlock) -> String {
        switch block {
        case .text:
            return "text"
        case .toolCall:
            return "toolCall"
        case .subAgent:
            return "subAgent"
        case .compactBoundary:
            return "compactBoundary"
        case .result:
            return "result"
        case .error:
            return "error"
        case .unknown:
            return "unknown"
        }
    }
}
