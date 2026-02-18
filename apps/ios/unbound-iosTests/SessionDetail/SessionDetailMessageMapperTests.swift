import Foundation
import XCTest

@testable import unbound_ios

final class SessionDetailMessageMapperTests: XCTestCase {
    func testMapRowsGroupsSubAgentToolUsesAcrossMessages() {
        let taskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"Explore","description":"Search codebase"}}]}}"#
        let childReadPayload = #"{"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_1","name":"Read","input":{"file_path":"README.md"}}]}}"#
        let childGrepPayload = #"{"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_2","name":"Grep","input":{"pattern":"TODO"}}]}}"#

        let rows = [
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 3,
                createdAt: Date(timeIntervalSince1970: 30),
                content: childGrepPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 2,
                createdAt: Date(timeIntervalSince1970: 20),
                content: childReadPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 1,
                createdAt: Date(timeIntervalSince1970: 10),
                content: taskPayload
            ),
        ]

        let result = SessionDetailMessageMapper.mapRows(rows, totalMessageCount: rows.count)

        XCTAssertEqual(result.decryptedMessageCount, 3)
        XCTAssertEqual(result.messages.count, 1)

        guard let blocks = result.messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one grouped sub-agent block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_1")
        XCTAssertEqual(activity.subagentType, "Explore")
        XCTAssertEqual(activity.tools.count, 2)
        XCTAssertEqual(activity.tools.map(\.toolName), ["Read", "Grep"])
    }

    func testMapRowsMergesDuplicateSubAgentActivitiesAndDeduplicatesToolsById() {
        let initialTaskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"general-purpose","description":"Initial scan"}}]}}"#
        let updatedTaskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"Plan","description":"Critical review"}}]}}"#
        let firstToolPayload = #"{"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_read","name":"Read","input":{"file_path":"README.md"}}]}}"#
        let secondToolPayload = #"{"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_read","name":"Read","input":{"file_path":"docs/README.md"}}]}}"#

        let rows = [
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 4,
                createdAt: Date(timeIntervalSince1970: 40),
                content: secondToolPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 3,
                createdAt: Date(timeIntervalSince1970: 30),
                content: firstToolPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 2,
                createdAt: Date(timeIntervalSince1970: 20),
                content: updatedTaskPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 1,
                createdAt: Date(timeIntervalSince1970: 10),
                content: initialTaskPayload
            ),
        ]

        let result = SessionDetailMessageMapper.mapRows(rows, totalMessageCount: rows.count)

        XCTAssertEqual(result.decryptedMessageCount, 4)
        XCTAssertEqual(result.messages.count, 1)

        guard let blocks = result.messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one merged sub-agent block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_1")
        XCTAssertEqual(activity.subagentType, "Plan")
        XCTAssertEqual(activity.description, "Critical review")
        XCTAssertEqual(activity.tools.count, 1)
        XCTAssertEqual(activity.tools.first?.toolUseId, "tool_read")
        XCTAssertEqual(activity.tools.first?.summary, "Read docs/README.md")
    }

    func testMapRowsHandlesNestedRawJsonAndResultVisibilityRules() {
        let wrappedAssistant = #"{"raw_json":"{\"raw_json\":\"{\\\"type\\\":\\\"assistant\\\",\\\"message\\\":{\\\"role\\\":\\\"assistant\\\",\\\"content\\\":[{\\\"type\\\":\\\"text\\\",\\\"text\\\":\\\"nested assistant\\\"}]}}\"}"}"#
        let wrappedSuccessResult = #"{"raw_json":"{\"type\":\"result\",\"is_error\":false,\"result\":\"ok\"}"}"#
        let wrappedErrorResult = #"{"raw_json":"{\"type\":\"result\",\"is_error\":true,\"result\":\"boom\"}"}"#

        let rows = [
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 1,
                createdAt: Date(timeIntervalSince1970: 10),
                content: wrappedAssistant
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 2,
                createdAt: Date(timeIntervalSince1970: 20),
                content: wrappedSuccessResult
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 3,
                createdAt: Date(timeIntervalSince1970: 30),
                content: wrappedErrorResult
            ),
        ]

        let result = SessionDetailMessageMapper.mapRows(rows, totalMessageCount: rows.count)

        XCTAssertEqual(result.decryptedMessageCount, 3)
        XCTAssertEqual(result.messages.count, 2)
        XCTAssertEqual(result.messages.first?.role, .assistant)
        XCTAssertEqual(result.messages.first?.content, "nested assistant")
        XCTAssertEqual(result.messages.last?.role, .system)
        XCTAssertEqual(result.messages.last?.content, "boom")
    }

    func testMapRowsDeduplicatesDuplicateMessageIdsWithLatestWriteWins() {
        let olderPayload = #"{"role":"assistant","content":"older content"}"#
        let newerPayload = #"{"role":"assistant","content":"newer content"}"#
        let trailingPayload = #"{"role":"assistant","content":"trailing content"}"#

        let rows = [
            SessionDetailPlaintextMessageRow(
                id: "dup-1",
                sequenceNumber: 1,
                createdAt: Date(timeIntervalSince1970: 10),
                content: olderPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: "tail-2",
                sequenceNumber: 2,
                createdAt: Date(timeIntervalSince1970: 20),
                content: trailingPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: "dup-1",
                sequenceNumber: 1,
                createdAt: Date(timeIntervalSince1970: 30),
                content: newerPayload
            ),
        ]

        let result = SessionDetailMessageMapper.mapRows(rows)

        XCTAssertEqual(result.decryptedMessageCount, 2)
        XCTAssertEqual(result.messages.map(\.content), ["newer content", "trailing content"])
        XCTAssertEqual(result.messages.map(\.role), [.assistant, .assistant])
    }

    func testMapRowsSortsSequenceTiesByCreatedAtThenRowId() {
        let earlyPayload = #"{"role":"assistant","content":"first"}"#
        let middlePayload = #"{"role":"assistant","content":"second"}"#
        let latePayload = #"{"role":"assistant","content":"third"}"#

        let rows = [
            SessionDetailPlaintextMessageRow(
                id: "row-c",
                sequenceNumber: 42,
                createdAt: Date(timeIntervalSince1970: 20),
                content: latePayload
            ),
            SessionDetailPlaintextMessageRow(
                id: "row-b",
                sequenceNumber: 42,
                createdAt: Date(timeIntervalSince1970: 20),
                content: middlePayload
            ),
            SessionDetailPlaintextMessageRow(
                id: "row-a",
                sequenceNumber: 42,
                createdAt: Date(timeIntervalSince1970: 10),
                content: earlyPayload
            ),
        ]

        let result = SessionDetailMessageMapper.mapRows(rows, totalMessageCount: rows.count)

        XCTAssertEqual(result.decryptedMessageCount, 3)
        XCTAssertEqual(result.messages.map(\.content), ["first", "second", "third"])
    }

    func testMapRowsKeepsStableSubAgentStatusAndResultAcrossRepeatedTaskUpdates() {
        let completedTaskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_status_merge","name":"Task","status":"completed","input":{"subagent_type":"Explore","description":"Investigate parser parity"},"result":"Completed parser parity investigation"}]}}"#
        let staleRunningTaskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_status_merge","name":"Task","status":"running","input":{"subagent_type":"Explore","description":"Investigate parser parity"}}]}}"#
        let childToolPayload = #"{"type":"assistant","parent_tool_use_id":"task_status_merge","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_status_child","name":"Read","status":"completed","input":{"file_path":"MessageBubbleView.swift"},"result":"loaded 410 lines"}]}}"#

        let rows = [
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 1,
                createdAt: Date(timeIntervalSince1970: 10),
                content: completedTaskPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 2,
                createdAt: Date(timeIntervalSince1970: 20),
                content: staleRunningTaskPayload
            ),
            SessionDetailPlaintextMessageRow(
                id: UUID().uuidString,
                sequenceNumber: 3,
                createdAt: Date(timeIntervalSince1970: 30),
                content: childToolPayload
            ),
        ]

        let result = SessionDetailMessageMapper.mapRows(rows, totalMessageCount: rows.count)
        XCTAssertEqual(result.messages.count, 1)

        guard let blocks = result.messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one merged sub-agent block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_status_merge")
        XCTAssertEqual(activity.status, .completed, "Completed status should not regress to running")
        XCTAssertEqual(activity.result, "Completed parser parity investigation")
        XCTAssertEqual(activity.tools.count, 1)
        XCTAssertEqual(activity.tools.first?.toolUseId, "task_status_child")
        XCTAssertEqual(activity.tools.first?.status, .completed)
    }
}
