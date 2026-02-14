//
//  ClaudeMessageParserContractTests.swift
//  unbound-macosTests
//
//  Contract tests for historical parser behavior.
//

import XCTest
@testable import unbound_macos

final class ClaudeMessageParserContractTests: XCTestCase {

    func testAssistantTextAndToolUseParsing() {
        let assistantPayload = jsonString([
            "type": "assistant",
            "message": [
                "content": [
                    ["type": "text", "text": "Reviewing parser contracts"],
                    [
                        "type": "tool_use",
                        "id": "tool_text_mix",
                        "name": "Read",
                        "input": ["file_path": "SessionLiveState.swift"]
                    ]
                ]
            ]
        ])

        let parsed = parse(assistantPayload)
        XCTAssertEqual(parsed?.role, .assistant)
        XCTAssertEqual(parsed?.textContent, "Reviewing parser contracts")

        let toolUses = parsed?.content.compactMap { content -> ToolUse? in
            guard case .toolUse(let toolUse) = content else { return nil }
            return toolUse
        } ?? []
        XCTAssertEqual(toolUses.count, 1)
        XCTAssertEqual(toolUses.first?.toolUseId, "tool_text_mix")
    }

    func testWrappedRawJSONAssistantIsParsed() {
        let assistantPayload = jsonString([
            "type": "assistant",
            "message": [
                "content": [
                    ["type": "text", "text": "Planning parser contract changes"]
                ]
            ]
        ])

        let wrapped = jsonString(["raw_json": assistantPayload])
        let parsed = parse(wrapped)

        XCTAssertEqual(parsed?.role, .assistant)
        XCTAssertEqual(parsed?.textContent, "Planning parser contract changes")
    }

    func testResultSuccessIsHiddenAndResultErrorIsVisible() {
        let success = jsonString([
            "type": "result",
            "is_error": false,
            "result": "All good"
        ])
        let error = jsonString([
            "type": "result",
            "is_error": true,
            "result": "Tool failed with exit code 1"
        ])

        XCTAssertNil(parse(success))

        let errorMessage = parse(error)
        XCTAssertEqual(errorMessage?.role, .system)
        XCTAssertEqual(errorMessage?.textContent, "Error: Tool failed with exit code 1")
    }

    func testWrappedResultSuccessHiddenAndWrappedResultErrorVisible() {
        let wrappedSuccess = jsonString([
            "raw_json": jsonString([
                "type": "result",
                "is_error": false,
                "result": "Wrapped success"
            ])
        ])
        let wrappedError = jsonString([
            "raw_json": jsonString([
                "type": "result",
                "is_error": true,
                "result": "Wrapped failure"
            ])
        ])

        XCTAssertNil(parse(wrappedSuccess))

        let parsedError = parse(wrappedError)
        XCTAssertEqual(parsedError?.role, .system)
        XCTAssertEqual(parsedError?.textContent, "Error: Wrapped failure")
    }

    func testUserProtocolArtifactOnlyRowIsHidden() {
        let artifactToolResult = jsonString([
            "type": "assistant",
            "message": [
                "content": [
                    ["type": "text", "text": "protocol artifact"]
                ]
            ]
        ])

        let userPayload = jsonString([
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": "tool_1",
                        "content": artifactToolResult
                    ]
                ]
            ]
        ])

        XCTAssertNil(parse(userPayload))
    }

    func testUserRealTextIsPreservedWhenArtifactExists() {
        let artifactToolResult = jsonString([
            "type": "assistant",
            "message": [
                "content": [
                    ["type": "text", "text": "protocol artifact"]
                ]
            ]
        ])

        let userPayload = jsonString([
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": "tool_1",
                        "content": artifactToolResult
                    ],
                    [
                        "type": "text",
                        "text": "Please keep this user-visible text"
                    ]
                ]
            ]
        ])

        let parsed = parse(userPayload)
        XCTAssertEqual(parsed?.role, .user)
        XCTAssertEqual(parsed?.textContent, "Please keep this user-visible text")
    }

    func testDuplicateToolUseInAssistantMessageKeepsLatestState() {
        let assistantPayload = jsonString([
            "type": "assistant",
            "message": [
                "content": [
                    [
                        "type": "tool_use",
                        "id": "tool_dup",
                        "name": "Read",
                        "input": ["file_path": "README.md"]
                    ],
                    [
                        "type": "tool_use",
                        "id": "tool_dup",
                        "name": "Read",
                        "input": ["file_path": "ARCHITECTURE.md"]
                    ]
                ]
            ]
        ])

        let parsed = parse(assistantPayload)
        XCTAssertEqual(parsed?.role, .assistant)

        let toolUses = parsed?.content.compactMap { content -> ToolUse? in
            guard case .toolUse(let toolUse) = content else { return nil }
            return toolUse
        } ?? []

        XCTAssertEqual(toolUses.count, 1)
        XCTAssertEqual(toolUses.first?.toolUseId, "tool_dup")
        XCTAssertTrue(toolUses.first?.input?.contains("ARCHITECTURE.md") == true)
    }

    func testUnknownPayloadFallsBackToDeterministicSystemText() {
        let unknown = jsonString([
            "type": "unknown_protocol_type",
            "foo": "bar"
        ])

        let parsed = parse(unknown)
        XCTAssertEqual(parsed?.role, .system)
        XCTAssertTrue(parsed?.textContent.contains("\"type\":\"unknown_protocol_type\"") == true)
    }

    func testMalformedWrappedRawJSONFallsBackToDeterministicSystemText() {
        let malformedWrapped = jsonString([
            "raw_json": "{not-json"
        ])

        let parsed = parse(malformedWrapped)
        XCTAssertEqual(parsed?.role, .system)
        XCTAssertTrue(parsed?.textContent.contains("\"raw_json\":\"{not-json\"") == true)
    }

    private func parse(_ json: String) -> ChatMessage? {
        ClaudeMessageParser.parseMessage(makeDaemonMessage(content: json))
    }

    private func makeDaemonMessage(content: String) -> DaemonMessage {
        DaemonMessage(
            id: UUID().uuidString,
            sessionId: UUID().uuidString,
            content: content,
            sequenceNumber: 0,
            timestamp: nil,
            isStreaming: nil
        )
    }

    private func jsonString(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }
}
