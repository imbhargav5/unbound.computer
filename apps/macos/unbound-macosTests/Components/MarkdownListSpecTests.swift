import XCTest

@testable import unbound_macos

final class MarkdownListSpecTests: XCTestCase {
    func testOrderedListPreservesSourceMarkers() {
        let markdown = """
        3. Third item
        7) Seventh item
        12. Twelfth item
        """

        let blocks = MarkdownParserDebug.parse(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .numberedList(let items) = blocks[0] else {
            return XCTFail("Expected a numbered list block")
        }

        XCTAssertEqual(items.map(\.marker), ["3.", "7)", "12."])
        XCTAssertEqual(items.map(\.text), ["Third item", "Seventh item", "Twelfth item"])
    }

    func testParserSegmentsParagraphBulletAndNumberedLists() {
        let markdown = """
        Intro paragraph line
        - Bullet one
        - Bullet two

        1. Ordered one
        2) Ordered two
        """

        let blocks = MarkdownParserDebug.parse(markdown)

        XCTAssertEqual(blocks.count, 3)

        guard case .listHeading(let heading) = blocks[0] else {
            return XCTFail("First block should be promoted list heading")
        }
        XCTAssertEqual(heading, "Intro paragraph line")

        guard case .bulletList(let bulletItems) = blocks[1] else {
            return XCTFail("Second block should be bullet list")
        }
        XCTAssertEqual(bulletItems.map(\.text), ["Bullet one", "Bullet two"])

        guard case .numberedList(let orderedItems) = blocks[2] else {
            return XCTFail("Third block should be ordered list")
        }
        XCTAssertEqual(orderedItems.map(\.marker), ["1.", "2)"])
        XCTAssertEqual(orderedItems.map(\.text), ["Ordered one", "Ordered two"])
    }

    func testSingleLineParagraphPromotedToListHeading() {
        let markdown = """
        Getting Started
        1. Clone the repository
        2. Configure environment variables
        """

        let blocks = MarkdownParserDebug.parse(markdown)
        XCTAssertEqual(blocks.count, 2)

        guard case .listHeading(let heading) = blocks[0] else {
            return XCTFail("Expected list heading before list")
        }
        XCTAssertEqual(heading, "Getting Started")

        guard case .numberedList = blocks[1] else {
            return XCTFail("Expected numbered list after promoted heading")
        }
    }

    func testMultiLineParagraphNotPromotedToListHeading() {
        let markdown = """
        This is a sentence
        split across two lines.
        - Item 1
        """

        let blocks = MarkdownParserDebug.parse(markdown)
        XCTAssertEqual(blocks.count, 2)

        guard case .paragraph(let paragraph) = blocks[0] else {
            return XCTFail("Expected paragraph block to remain unchanged")
        }
        XCTAssertEqual(paragraph, "This is a sentence\nsplit across two lines.")
    }

    func testListIndentParsingForSpacesAndTabs() {
        let markdown = """
        - Root
          - Child
        \t- Tab child
            - Deep child
        """

        let blocks = MarkdownParserDebug.parse(markdown)

        XCTAssertEqual(blocks.count, 1)
        guard case .bulletList(let items) = blocks[0] else {
            return XCTFail("Expected a bullet list block")
        }

        XCTAssertEqual(items.map(\.indent), [0, 1, 1, 2])
        XCTAssertEqual(items.map(\.text), ["Root", "Child", "Tab child", "Deep child"])
    }

    func testMarkdownListTokensMatchPencilSpecs() {
        XCTAssertEqual(MarkdownListTokens.listPaddingTop, 4, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.listPaddingRight, 0, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.listPaddingBottom, 4, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.listPaddingLeft, 16, accuracy: 0.001)

        XCTAssertEqual(MarkdownListTokens.itemVerticalSpacing, 4, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.markerToTextSpacing, 8, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.indentStep, 16, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.orderedMarkerColumnWidth, 16, accuracy: 0.001)

        XCTAssertEqual(MarkdownListTokens.markerFontSize, 13, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.itemTextFontSize, 13, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.headingFontSize, 14, accuracy: 0.001)
        XCTAssertEqual(MarkdownListTokens.headingBottomSpacing, 8, accuracy: 0.001)
    }

    func testMarkdownProseTokensMatchPencilSpecs() {
        XCTAssertEqual(MarkdownProseTokens.paragraphFontSize, 13, accuracy: 0.001)
        XCTAssertEqual(MarkdownProseTokens.headingH1FontSize, 22, accuracy: 0.001)
        XCTAssertEqual(MarkdownProseTokens.headingH2FontSize, 17, accuracy: 0.001)
        XCTAssertEqual(MarkdownProseTokens.headingH3FontSize, 14, accuracy: 0.001)

        XCTAssertEqual(MarkdownProseTokens.inlineCodeFontSize, 12, accuracy: 0.001)
        XCTAssertEqual(MarkdownProseTokens.inlineCodeCornerRadius, 4, accuracy: 0.001)
        XCTAssertEqual(MarkdownProseTokens.inlineCodePaddingVertical, 2, accuracy: 0.001)
        XCTAssertEqual(MarkdownProseTokens.inlineCodePaddingHorizontal, 6, accuracy: 0.001)
    }
}
