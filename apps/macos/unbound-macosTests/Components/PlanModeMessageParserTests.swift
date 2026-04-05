import XCTest
@testable import unbound_macos

final class PlanModeMessageParserTests: XCTestCase {
    func testParsesPlanModeMarkdownFromLogShape() {
        let markdown = """
        ## Design Language Consistency Plan

        ### Summary
        Unify the design language between web and macOS.

        ### Public API / Type Changes
        1. Update token naming in shared styles.
        2. Keep old aliases during migration.

        ### Implementation Plan
        1. Add shared token file.
        2. Update button/card/input styles.
        3. Add parity tests.
        """

        let parsed = PlanModeMessageParser.parse(markdown)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.title, "Design Language Consistency Plan")
        XCTAssertTrue(parsed?.bodyMarkdown.contains("Implementation Plan") == true)
        XCTAssertTrue(parsed?.bodyMarkdown.contains("1. Add shared token file.") == true)
    }

    func testParsesPlanWithoutLeadingHeading() {
        let markdown = """
        Plan for improving parser resilience

        ## Summary
        Handle malformed blocks safely.

        ## Implementation Plan
        1. Decode blocks one-by-one.
        2. Skip malformed blocks.
        """

        let parsed = PlanModeMessageParser.parse(markdown)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.title, "Plan for improving parser resilience")
    }

    func testReturnsNilForNonPlanText() {
        let text = """
        Here is a quick update:
        - looked at the code
        - confirmed current behavior
        """

        XCTAssertNil(PlanModeMessageParser.parse(text))
    }

    func testReturnsNilWhenMissingNumberedSteps() {
        let text = """
        ## Plan

        ### Summary
        This has no numbered implementation steps.
        """

        XCTAssertNil(PlanModeMessageParser.parse(text))
    }
}
