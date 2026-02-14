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

    func testToolResultErrorUpdatesStandaloneStatusToFailed() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "tool_fail", name: "Bash", input: ["command": "exit 1"])
        ]))

        state.ingestClaudeEventForTests(userToolResultEvent(toolUseId: "tool_fail", isError: true))

        XCTAssertEqual(state.activeTools.first?.status, .failed)
    }

    func testDuplicateStandaloneToolUseKeepsLatestState() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "tool_dup", name: "Read", input: ["file_path": "README.md"])
        ]))
        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "tool_dup", name: "Read", input: ["file_path": "ARCHITECTURE.md"])
        ]))

        XCTAssertEqual(state.activeTools.count, 1)
        XCTAssertEqual(state.activeTools.first?.id, "tool_dup")
        XCTAssertEqual(state.activeTools.first?.inputPreview, "ARCHITECTURE.md")
    }

    func testDuplicateChildToolUseKeepsLatestState() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "task_dup", name: "Task", input: ["subagent_type": "Explore", "description": "Search codebase"])
        ]))

        state.ingestClaudeEventForTests(assistantEvent(
            toolUses: [toolUse(id: "tool_child_dup", name: "Read", input: ["file_path": "README.md"])],
            parent: "task_dup"
        ))

        state.ingestClaudeEventForTests(assistantEvent(
            toolUses: [toolUse(id: "tool_child_dup", name: "Read", input: ["file_path": "ARCHITECTURE.md"])],
            parent: "task_dup"
        ))

        XCTAssertEqual(state.activeSubAgents.first?.childTools.count, 1)
        XCTAssertEqual(state.activeSubAgents.first?.childTools.first?.id, "tool_child_dup")
        XCTAssertEqual(state.activeSubAgents.first?.childTools.first?.inputPreview, "ARCHITECTURE.md")
    }

    func testWrappedRawJSONUserToolResultUpdatesStatus() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "tool_wrapped_result", name: "Read", input: ["file_path": "README.md"])
        ]))

        let wrapped = wrappedRawJSON(userToolResultEvent(toolUseId: "tool_wrapped_result"))
        state.ingestClaudeEventForTests(wrapped)

        XCTAssertEqual(state.activeTools.first?.status, .completed)
    }

    func testWrappedRawJSONResultErrorFinalizesRunningToolsAsFailed() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "tool_wrapped_error", name: "Read", input: ["file_path": "README.md"])
        ]))

        let wrapped = wrappedRawJSON(resultEvent(isError: true, result: "failed"))
        state.ingestClaudeEventForTests(wrapped)

        XCTAssertTrue(state.activeTools.isEmpty)
        XCTAssertEqual(state.toolHistory.first?.tools.first?.status, .failed)
    }

    func testResultSuccessFinalizesRunningStatesAndMovesToHistory() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "task_result_success", name: "Task", input: ["subagent_type": "Explore", "description": "Result finalize"])
        ]))
        state.ingestClaudeEventForTests(assistantEvent(
            toolUses: [toolUse(id: "child_result_success", name: "Read", input: ["file_path": "README.md"])],
            parent: "task_result_success"
        ))
        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "standalone_result_success", name: "Grep", input: ["pattern": "raw_json"])
        ]))

        state.ingestClaudeEventForTests(resultEvent(isError: false))

        XCTAssertTrue(state.activeSubAgents.isEmpty)
        XCTAssertTrue(state.activeTools.isEmpty)

        let statuses = flattenedHistoryStatuses(state.toolHistory)
        XCTAssertFalse(statuses.contains(.running))
        XCTAssertTrue(statuses.allSatisfy { $0 == .completed })
    }

    func testResultErrorFinalizesRunningStatesAsFailedAndMovesToHistory() {
        let state = SessionLiveState(sessionId: UUID())

        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "task_result_error", name: "Task", input: ["subagent_type": "Explore", "description": "Result finalize error"])
        ]))
        state.ingestClaudeEventForTests(assistantEvent(
            toolUses: [toolUse(id: "child_result_error", name: "Read", input: ["file_path": "README.md"])],
            parent: "task_result_error"
        ))
        state.ingestClaudeEventForTests(assistantEvent(toolUses: [
            toolUse(id: "standalone_result_error", name: "Bash", input: ["command": "echo fail"])
        ]))

        state.ingestClaudeEventForTests(resultEvent(isError: true, result: "failure"))

        XCTAssertTrue(state.activeSubAgents.isEmpty)
        XCTAssertTrue(state.activeTools.isEmpty)

        let statuses = flattenedHistoryStatuses(state.toolHistory)
        XCTAssertFalse(statuses.contains(.running))
        XCTAssertTrue(statuses.allSatisfy { $0 == .failed })
    }

    func testHistoricalAndLiveSemanticParityForSubAgentAndStandaloneTools() {
        let state = SessionLiveState(sessionId: UUID())

        let events = [
            assistantEvent(toolUses: [
                toolUse(id: "task_parity", name: "Task", input: ["subagent_type": "Explore", "description": "Parity"])
            ]),
            assistantEvent(
                toolUses: [toolUse(id: "child_parity", name: "Read", input: ["file_path": "README.md"])],
                parent: "task_parity"
            ),
            assistantEvent(toolUses: [
                toolUse(id: "standalone_parity", name: "Grep", input: ["pattern": "TODO"])
            ]),
        ]

        for event in events {
            state.ingestClaudeEventForTests(event)
        }

        let parsedMessages = events.enumerated().compactMap { index, json in
            ClaudeMessageParser.parseMessage(makeDaemonMessage(content: json, sequenceNumber: index))
        }
        let groupedHistorical = ChatMessageGrouper.groupSubAgentTools(messages: parsedMessages)

        let historicalSubAgent = groupedHistorical.flatMap(\.content).compactMap { content -> SubAgentActivity? in
            guard case .subAgentActivity(let activity) = content else { return nil }
            return activity
        }.first

        let historicalStandaloneToolIds = groupedHistorical.flatMap(\.content).compactMap { content -> String? in
            guard case .toolUse(let toolUse) = content else { return nil }
            return toolUse.toolUseId
        }

        XCTAssertEqual(state.activeSubAgents.count, 1)
        XCTAssertEqual(state.activeSubAgents.first?.id, historicalSubAgent?.parentToolUseId)
        XCTAssertEqual(
            state.activeSubAgents.first?.childTools.map(\.id),
            historicalSubAgent?.tools.compactMap(\.toolUseId)
        )
        XCTAssertEqual(state.activeTools.map(\.id), historicalStandaloneToolIds)
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

    private func userToolResultEvent(toolUseId: String, isError: Bool = false) -> String {
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": toolUseId,
                        "is_error": isError
                    ]
                ]
            ]
        ]
        return jsonString(payload)
    }

    private func resultEvent(isError: Bool, result: String = "done") -> String {
        jsonString([
            "type": "result",
            "is_error": isError,
            "result": result
        ])
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

    private func makeDaemonMessage(content: String, sequenceNumber: Int) -> DaemonMessage {
        DaemonMessage(
            id: UUID().uuidString,
            sessionId: UUID().uuidString,
            content: content,
            sequenceNumber: sequenceNumber,
            timestamp: nil,
            isStreaming: nil
        )
    }

    private func flattenedHistoryStatuses(_ history: [ToolHistoryEntry]) -> [ToolStatus] {
        history.flatMap { entry in
            var statuses = entry.tools.map(\.status)
            if let subAgent = entry.subAgent {
                statuses.append(subAgent.status)
                statuses.append(contentsOf: subAgent.childTools.map(\.status))
            }
            return statuses
        }
    }

    private func wrappedRawJSON(_ rawJSON: String) -> String {
        jsonString(["raw_json": rawJSON])
    }
}
