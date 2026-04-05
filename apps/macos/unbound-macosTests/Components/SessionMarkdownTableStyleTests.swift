import XCTest
import ClaudeConversationTimeline

@testable import unbound_macos

final class SessionMarkdownTableStyleTests: XCTestCase {
    func testFileLikeHeaderDetection() {
        let headers = [" File ", "Purpose", "TARGET", "Owner", " file   path "]

        let indices = MarkdownTableLayoutHelper.fileLikeColumnIndices(headers: headers)

        XCTAssertEqual(indices, Set([0, 2, 4]))
        XCTAssertEqual(MarkdownTableLayoutHelper.normalizedHeader("  File   Path "), "file path")
    }

    func testTableSectionHeadingDetection() {
        XCTAssertEqual(
            SessionMarkdownTableTextLayout.headingText(from: "### Agent Runtime & Session"),
            "Agent Runtime & Session"
        )
        XCTAssertNil(
            SessionMarkdownTableTextLayout.headingText(
                from: "### Agent Runtime & Session\nMore details below."
            )
        )
        XCTAssertNil(SessionMarkdownTableTextLayout.headingText(from: "Agent Runtime & Session"))
    }

    func testTransitionSpacingForHeadingTableSections() {
        let kinds: [SessionMarkdownTableTextLayout.SegmentKind] = [.heading, .table, .heading, .table]
        let spacings = kinds.indices.map { SessionMarkdownTableTextLayout.topPadding(for: kinds, at: $0) }

        XCTAssertEqual(spacings[0], 0, accuracy: 0.001)
        XCTAssertEqual(spacings[1], 8, accuracy: 0.001)
        XCTAssertEqual(spacings[2], 24, accuracy: 0.001)
        XCTAssertEqual(spacings[3], 8, accuracy: 0.001)
    }

    func testRowNormalizationRetainsColumnCount() {
        let normalized = MarkdownTableLayoutHelper.normalize(
            headers: ["File", "Purpose", "Owner"],
            rows: [["apps/ios/CryptoService.swift", "X25519"], ["apps/ios/CryptoUtils.swift"]],
            alignments: [.leading, .leading, .trailing]
        )

        XCTAssertEqual(normalized.columnCount, 3)
        XCTAssertEqual(normalized.headers.count, 3)
        XCTAssertEqual(normalized.rows.count, 2)
        XCTAssertEqual(normalized.rows[0].count, 3)
        XCTAssertEqual(normalized.rows[1].count, 3)
        XCTAssertEqual(normalized.rows[0][2], "")
        XCTAssertEqual(normalized.rows[1][1], "")
        XCTAssertEqual(normalized.rows[1][2], "")
    }
}
