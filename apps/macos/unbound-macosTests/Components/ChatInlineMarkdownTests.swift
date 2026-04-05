import XCTest

@testable import unbound_macos

final class ChatInlineMarkdownTests: XCTestCase {
    func testParsesLinksStrikethroughAndCodeWithDeterministicPrecedence() {
        let input = "Read [docs](https://example.com), avoid ~~legacy~~ and use **`config.json`**."

        let tokens = ChatInlineMarkdown.parse(input, options: .prose)

        XCTAssertTrue(tokens.contains(.link(label: "docs", url: "https://example.com")))
        XCTAssertTrue(tokens.contains(.strikethrough("legacy")))
        XCTAssertTrue(tokens.contains(.boldCode("config.json")))

        let codeTokenCount = tokens.filter {
            if case .code = $0 { return true }
            if case .boldCode = $0 { return true }
            return false
        }.count
        XCTAssertEqual(codeTokenCount, 1, "Bold code should not be split into separate bold/code tokens")
    }

    func testTableModeKeepsLinksAndStrikethroughLiteralButStillParsesCode() {
        let input = "[docs](https://example.com) ~~legacy~~ `config.json`"

        let tokens = ChatInlineMarkdown.parse(input, options: .table)

        XCTAssertTrue(tokens.contains(.code("config.json")))
        XCTAssertFalse(tokens.contains(where: {
            if case .link = $0 { return true }
            return false
        }))
        XCTAssertFalse(tokens.contains(where: {
            if case .strikethrough = $0 { return true }
            return false
        }))

        let rawText = tokens.compactMap { token -> String? in
            if case .text(let value) = token { return value }
            return nil
        }.joined()
        XCTAssertTrue(rawText.contains("[docs](https://example.com)"))
        XCTAssertTrue(rawText.contains("~~legacy~~"))
    }

    func testParsesItalicAndBoldWithoutOverlappingRanges() {
        let input = "Use **strong** and *emphasis* together."
        let tokens = ChatInlineMarkdown.parse(input, options: .prose)

        XCTAssertTrue(tokens.contains(.bold("strong")))
        XCTAssertTrue(tokens.contains(.italic("emphasis")))
    }
}
