//
//  SessionLiveStateStreamingTests.swift
//  unbound-macosTests
//
//  Tests live state updates as Claude JSON events stream in.
//

import XCTest
@testable import unbound_macos

final class SessionLiveStateStreamingTests: XCTestCase {

    func testTaskCreatesActiveSubAgent() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "task_1", name: "Task", input: ["subagent_type": "Explore", "description": "Search codebase"])
        ]))

        XCTAssertEqual(state.activeSubAgents.count, 1)
        XCTAssertEqual(state.activeSubAgents.first?.id, "task_1")
        XCTAssertEqual(state.activeSubAgents.first?.subagentType, "Explore")
    }

    func testMessageParentAttachesChildTool() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "task_1", name: "Task", input: ["subagent_type": "Explore", "description": "Search codebase"])
        ]))

        state.ingestClaudeEventForTests(assistantEvent(
            toolUses: [toolUse(id: "tool_1", name: "Read", input: ["file_path": "README.md"])],
            parent: "task_1"
        ))

        XCTAssertEqual(state.activeSubAgents.first?.childTools.count, 1)
        XCTAssertEqual(state.activeSubAgents.first?.childTools.first?.id, "tool_1")
    }

    func testChildBeforeTaskQueuesAndAttaches() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(
            toolUses: [toolUse(id: "tool_2", name: "Read", input: ["file_path": "ARCHITECTURE.md"])],
            parent: "task_2"
        ))

        XCTAssertEqual(state.activeSubAgents.count, 0)
        XCTAssertEqual(state.activeTools.count, 0)

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "task_2", name: "Task", input: ["subagent_type": "Explore", "description": "Read docs"])
        ]))

        XCTAssertEqual(state.activeSubAgents.count, 1)
        XCTAssertEqual(state.activeSubAgents.first?.childTools.count, 1)
        XCTAssertEqual(state.activeSubAgents.first?.childTools.first?.id, "tool_2")
    }

    func testToolResultUpdatesChildStatus() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "task_3", name: "Task", input: ["subagent_type": "Explore", "description": "Search"])
        ]))

        state.ingestClaudeEventForTests(assistantEvent(
            toolUses: [toolUse(id: "tool_3", name: "Grep", input: ["pattern": "armin"])],
            parent: "task_3"
        ))

        XCTAssertEqual(state.activeSubAgents.first?.childTools.first?.status, .running)

        state.ingestClaudeEventForTests(userToolResultEvent(toolUseId: "tool_3"))

        XCTAssertEqual(state.activeSubAgents.first?.childTools.first?.status, .completed)
    }

    // MARK: - Helpers

    private func assistantEvent(toolUses: [[String: Any]], parent: String? = nil) -> String {
        var payload: [String: Any] = [
            "type": "assistant",
            "message": [
                "content": toolUses
            ]
        ]
        if let parent {
            payload["parent_tool_use_id"] = parent
        }
        return jsonString(payload)
    }

    private func userToolResultEvent(toolUseId: String) -> String {
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": toolUseId,
                        "is_error": false
                    ]
                ]
            ]
        ]
        return jsonString(payload)
    }

    private func toolUse(id: String, name: String, input: [String: Any]) -> [String: Any] {
        [
            "type": "tool_use",
            "id": id,
            "name": name,
            "input": input
        ]
    }

    private func jsonString(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }
}
