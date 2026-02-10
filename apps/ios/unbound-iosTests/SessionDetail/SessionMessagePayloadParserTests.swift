import XCTest

@testable import unbound_ios

final class SessionMessagePayloadParserTests: XCTestCase {
    func testRoleUsesEncryptedPayloadRoleField() {
        let role = SessionMessagePayloadParser.role(from: #"{"role":"assistant","content":"hello"}"#)
        XCTAssertEqual(role, .assistant)
    }

    func testRoleFallsBackToTypeWhenRoleMissing() {
        let role = SessionMessagePayloadParser.role(from: #"{"type":"user_prompt_command","content":"hello"}"#)
        XCTAssertEqual(role, .user)
    }

    func testDisplayTextReadsContentFragments() {
        let text = SessionMessagePayloadParser.displayText(
            from: #"{"content":[{"text":"line 1"},{"content":"line 2"}]}"#
        )
        XCTAssertEqual(text, "line 1\nline 2")
    }

    func testDisplayTextReturnsPlaintextForNonJson() {
        let text = SessionMessagePayloadParser.displayText(from: "plain text payload")
        XCTAssertEqual(text, "plain text payload")
    }
}
