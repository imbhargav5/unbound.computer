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

    func testStatusChangeRuntimeEnvelopeTransitionFlow() {
        let sessionId = UUID()
        let state = SessionLiveState(sessionId: sessionId)
        let normalizedSessionId = sessionId.uuidString.lowercased()

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "running",
                updatedAtMs: 1_000
            )
        )
        XCTAssertEqual(state.codingSessionStatus, .running)
        XCTAssertTrue(state.claudeRunning)
        XCTAssertTrue(state.canSendMessage)
        XCTAssertNil(state.codingSessionErrorMessage)

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "waiting",
                updatedAtMs: 1_100
            )
        )
        XCTAssertEqual(state.codingSessionStatus, .waiting)
        XCTAssertTrue(state.claudeRunning)

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "running",
                updatedAtMs: 1_200
            )
        )
        XCTAssertEqual(state.codingSessionStatus, .running)
        XCTAssertTrue(state.claudeRunning)

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "idle",
                updatedAtMs: 1_300
            )
        )
        XCTAssertEqual(state.codingSessionStatus, .idle)
        XCTAssertFalse(state.claudeRunning)

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "error",
                errorMessage: "daemon exploded",
                updatedAtMs: 1_400
            )
        )
        XCTAssertEqual(state.codingSessionStatus, .error)
        XCTAssertEqual(state.codingSessionErrorMessage, "daemon exploded")
        XCTAssertFalse(state.claudeRunning)

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "running",
                updatedAtMs: 1_500
            )
        )
        XCTAssertEqual(state.codingSessionStatus, .running)
        XCTAssertNil(state.codingSessionErrorMessage)
        XCTAssertTrue(state.claudeRunning)

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "not-available",
                updatedAtMs: 1_600
            )
        )
        XCTAssertEqual(state.codingSessionStatus, .notAvailable)
        XCTAssertFalse(state.canSendMessage)
        XCTAssertFalse(state.claudeRunning)
    }

    func testStatusChangeIgnoresStaleRuntimeEnvelopeByUpdatedAtMs() {
        let sessionId = UUID()
        let state = SessionLiveState(sessionId: sessionId)
        let normalizedSessionId = sessionId.uuidString.lowercased()

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "running",
                updatedAtMs: 2_000
            )
        )

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: normalizedSessionId,
                status: "idle",
                updatedAtMs: 1_999
            )
        )

        XCTAssertEqual(state.codingSessionStatus, .running)
        XCTAssertTrue(state.claudeRunning)
    }

    func testStatusChangeLegacyFallbackCompatibility() {
        let sessionId = UUID()
        let state = SessionLiveState(sessionId: sessionId)

        state.ingestDaemonEventForTests(
            legacyStatusChangeEvent(
                sessionId: sessionId.uuidString.lowercased(),
                status: "error",
                errorMessage: "legacy error",
                sequence: 7
            )
        )

        XCTAssertEqual(state.codingSessionStatus, .error)
        XCTAssertEqual(state.codingSessionErrorMessage, "legacy error")
        XCTAssertEqual(state.runtimeStatus?.schemaVersion, 1)
        XCTAssertEqual(state.runtimeStatus?.deviceId, "legacy-ipc")
        XCTAssertEqual(state.runtimeStatus?.updatedAtMs, 7)
    }

    func testUnknownRuntimeStatusFallsBackToNotAvailable() {
        let sessionId = UUID()
        let state = SessionLiveState(sessionId: sessionId)

        state.ingestDaemonEventForTests(
            runtimeStatusChangeEvent(
                sessionId: sessionId.uuidString.lowercased(),
                status: "definitely-new-status",
                updatedAtMs: 42
            )
        )

        XCTAssertEqual(state.codingSessionStatus, .notAvailable)
        XCTAssertFalse(state.canSendMessage)
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

    private func runtimeStatusChangeEvent(
        sessionId: String,
        status: String,
        errorMessage: String? = nil,
        updatedAtMs: Int64
    ) -> DaemonEvent {
        var codingSession: [String: Any] = ["status": status]
        if let errorMessage {
            codingSession["error_message"] = errorMessage
        }

        let runtimeStatus: [String: Any] = [
            "schema_version": 1,
            "coding_session": codingSession,
            "device_id": "device-test",
            "session_id": sessionId,
            "updated_at_ms": updatedAtMs
        ]

        var data: [String: AnyCodableValue] = [
            "status": AnyCodableValue(status),
            "runtime_status": AnyCodableValue(runtimeStatus)
        ]
        if let errorMessage {
            data["error_message"] = AnyCodableValue(errorMessage)
        }

        return DaemonEvent(
            type: .statusChange,
            sessionId: sessionId,
            data: data,
            sequence: updatedAtMs
        )
    }

    private func legacyStatusChangeEvent(
        sessionId: String,
        status: String,
        errorMessage: String?,
        sequence: Int64
    ) -> DaemonEvent {
        var data: [String: AnyCodableValue] = [
            "status": AnyCodableValue(status)
        ]
        if let errorMessage {
            data["error_message"] = AnyCodableValue(errorMessage)
        }

        return DaemonEvent(
            type: .statusChange,
            sessionId: sessionId,
            data: data,
            sequence: sequence
        )
    }
}
