//
//  ChatMessageGroupingTests.swift
//  unbound-macosTests
//
//  Tests grouping of sub-agent tool_use blocks across messages.
//

import XCTest
@testable import unbound_macos

final class ChatMessageGroupingTests: XCTestCase {

    func testGroupsChildToolsUnderTaskAcrossMessages() {
        let taskJson = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"Explore","description":"Search codebase"}}]}}
        """
        let childRead = """
        {"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_1","name":"Read","input":{"file_path":"README.md"}}]}}
        """
        let childGrep = """
        {"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_2","name":"Grep","input":{"pattern":"armin"}}]}}
        """

        let messages = parseMessages([taskJson, childRead, childGrep])
        let grouped = ChatMessageGrouper.groupSubAgentTools(messages: messages)

        let subAgent = firstSubAgent(in: grouped)
        XCTAssertNotNil(subAgent, "Expected a sub-agent activity to exist")
        XCTAssertEqual(subAgent?.tools.count, 2, "Expected child tools to be grouped under the Task sub-agent")
        XCTAssertEqual(grouped.count, 1, "Child-only messages should be removed after grouping")
    }

    func testChildBeforeTaskQueuesAndAttaches() {
        let childRead = """
        {"type":"assistant","parent_tool_use_id":"task_2","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_3","name":"Read","input":{"file_path":"ARCHITECTURE.md"}}]}}
        """
        let taskJson = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_2","name":"Task","input":{"subagent_type":"Explore","description":"Read docs"}}]}}
        """

        let messages = parseMessages([childRead, taskJson])
        let grouped = ChatMessageGrouper.groupSubAgentTools(messages: messages)

        let subAgent = firstSubAgent(in: grouped)
        XCTAssertNotNil(subAgent, "Expected a sub-agent activity to exist")
        XCTAssertEqual(subAgent?.tools.count, 1, "Expected queued child tool to attach when Task appears")
        XCTAssertEqual(grouped.count, 1, "Child-only message should be removed after grouping")
    }

    func testParentMissingLeavesStandalone() {
        let childOrphan = """
        {"type":"assistant","parent_tool_use_id":"missing_task","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_4","name":"Read","input":{"file_path":"README.md"}}]}}
        """

        let messages = parseMessages([childOrphan])
        let grouped = ChatMessageGrouper.groupSubAgentTools(messages: messages)

        XCTAssertEqual(grouped.count, 1, "Message should remain when parent task is missing")
        let toolUses = grouped.first?.content.compactMap { content -> ToolUse? in
            if case .toolUse(let toolUse) = content { return toolUse }
            return nil
        } ?? []
        XCTAssertEqual(toolUses.count, 1, "Orphaned tool should remain standalone")
        XCTAssertEqual(toolUses.first?.parentToolUseId, "missing_task")
    }

    func testMessageParentAppliedToToolUse() {
        let childRead = """
        {"type":"assistant","parent_tool_use_id":"task_3","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_5","name":"Read","input":{"file_path":"Cargo.toml"}}]}}
        """

        let messages = parseMessages([childRead])
        let toolUses = messages.first?.content.compactMap { content -> ToolUse? in
            if case .toolUse(let toolUse) = content { return toolUse }
            return nil
        } ?? []

        XCTAssertEqual(toolUses.count, 1)
        XCTAssertEqual(toolUses.first?.parentToolUseId, "task_3")
    }

    func testTextPreservedWhenToolMoved() {
        let taskJson = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_4","name":"Task","input":{"subagent_type":"Plan","description":"Plan changes"}}]}}
        """
        let childWithText = """
        {"type":"assistant","parent_tool_use_id":"task_4","message":{"role":"assistant","content":[{"type":"text","text":"Working on it"},{"type":"tool_use","id":"tool_6","name":"Grep","input":{"pattern":"todo"}}]}}
        """

        let messages = parseMessages([taskJson, childWithText])
        let grouped = ChatMessageGrouper.groupSubAgentTools(messages: messages)

        XCTAssertEqual(grouped.count, 2, "Text-only message should remain after tool is grouped")
        let textMessage = grouped.first { message in
            message.content.contains { content in
                if case .text = content { return true }
                return false
            }
        }
        XCTAssertNotNil(textMessage)

        let subAgent = firstSubAgent(in: grouped)
        XCTAssertEqual(subAgent?.tools.count, 1, "Child tool should be grouped under Task")
    }

    func testDuplicateChildToolUpdateKeepsLatestState() {
        let taskJson = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_dup","name":"Task","input":{"subagent_type":"Explore","description":"Search codebase"}}]}}
        """
        let childReadV1 = """
        {"type":"assistant","parent_tool_use_id":"task_dup","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_dup","name":"Read","input":{"file_path":"README.md"}}]}}
        """
        let childReadV2 = """
        {"type":"assistant","parent_tool_use_id":"task_dup","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_dup","name":"Read","input":{"file_path":"ARCHITECTURE.md"}}]}}
        """

        let messages = parseMessages([taskJson, childReadV1, childReadV2])
        let grouped = ChatMessageGrouper.groupSubAgentTools(messages: messages)

        let subAgent = firstSubAgent(in: grouped)
        XCTAssertEqual(subAgent?.tools.count, 1, "Expected duplicate tool updates to dedupe by tool_use_id")
        XCTAssertEqual(subAgent?.tools.first?.toolUseId, "tool_dup")
        XCTAssertTrue(subAgent?.tools.first?.input?.contains("ARCHITECTURE.md") == true)
    }

    func testStandaloneToolsRemainStandaloneWhenSubAgentGroupingOccurs() {
        let taskJson = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_keep","name":"Task","input":{"subagent_type":"Explore","description":"Search codebase"}}]}}
        """
        let childTool = """
        {"type":"assistant","parent_tool_use_id":"task_keep","message":{"role":"assistant","content":[{"type":"tool_use","id":"child_keep","name":"Read","input":{"file_path":"README.md"}}]}}
        """
        let standaloneTool = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"standalone_keep","name":"Bash","input":{"command":"swift test"}}]}}
        """

        let messages = parseMessages([taskJson, childTool, standaloneTool])
        let grouped = ChatMessageGrouper.groupSubAgentTools(messages: messages)

        XCTAssertEqual(grouped.count, 2, "Task + child should condense, standalone tool message should remain")

        let subAgent = firstSubAgent(in: grouped)
        XCTAssertNotNil(subAgent)
        XCTAssertEqual(subAgent?.tools.compactMap(\.toolUseId), ["child_keep"])

        let standaloneToolUses = grouped
            .flatMap(\.content)
            .compactMap { content -> ToolUse? in
                guard case .toolUse(let toolUse) = content else { return nil }
                return toolUse
            }

        XCTAssertEqual(standaloneToolUses.compactMap(\.toolUseId), ["standalone_keep"])
    }

    private func parseMessages(_ jsonMessages: [String]) -> [ChatMessage] {
        jsonMessages.enumerated().compactMap { index, json in
            let daemonMessage = DaemonMessage(
                id: UUID().uuidString,
                sessionId: "session",
                content: json,
                sequenceNumber: index,
                timestamp: nil,
                isStreaming: nil
            )
            return ClaudeMessageParser.parseMessage(daemonMessage)
        }
    }

    private func firstSubAgent(in messages: [ChatMessage]) -> SubAgentActivity? {
        for message in messages {
            for content in message.content {
                if case .subAgentActivity(let subAgent) = content {
                    return subAgent
                }
            }
        }
        return nil
    }
}
