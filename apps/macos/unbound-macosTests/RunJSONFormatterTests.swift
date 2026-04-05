//
//  RunJSONFormatterTests.swift
//  unbound-macosTests
//

import XCTest
@testable import unbound_macos

final class RunJSONFormatterTests: XCTestCase {

    func testObjectPayloadIsPrettyPrintedWithSortedKeys() {
        let value = AnyCodableValue([
            "b": 2,
            "a": 1,
        ])

        XCTAssertEqual(
            RunJSONFormatter.format(value),
            """
            {
              "a" : 1,
              "b" : 2
            }
            """
        )
    }

    func testArrayPayloadIsPrettyPrintedCleanly() {
        let value = AnyCodableValue([
            ["b": 2, "a": 1],
            3,
            "text",
        ])

        XCTAssertEqual(
            RunJSONFormatter.format(value),
            """
            [
              {
                "a" : 1,
                "b" : 2
              },
              3,
              "text"
            ]
            """
        )
    }

    func testScalarPayloadFallsBackToSimpleString() {
        XCTAssertEqual(RunJSONFormatter.format(AnyCodableValue("queued")), "queued")
        XCTAssertEqual(RunJSONFormatter.format(AnyCodableValue(42)), "42")
    }

    func testInvalidJSONTextIsPreservedVerbatim() {
        let raw = "{\"type\":not-json"

        XCTAssertEqual(RunJSONFormatter.formatJSONText(raw), raw)
        XCTAssertEqual(RunJSONFormatter.rawText(raw), raw)
    }
}
