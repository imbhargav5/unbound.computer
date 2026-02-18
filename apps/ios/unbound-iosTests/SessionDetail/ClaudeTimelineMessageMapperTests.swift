import Foundation
import MobileClaudeCodeConversationTimeline
import XCTest

@testable import unbound_ios

final class ClaudeTimelineMessageMapperTests: XCTestCase {
    func testMapEntriesDropsUserEntryWithProtocolArtifactOnlyText() {
        let entry = ClaudeConversationTimelineEntry(
            id: "user-envelope",
            role: .user,
            blocks: [.text(#"{"type":"assistant","message":{"content":[{"type":"text","text":"artifact"}]}}"#)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "user_prompt_command"
        )

        let messages = ClaudeTimelineMessageMapper.mapEntries([entry])

        XCTAssertTrue(messages.isEmpty)
    }

    func testMapEntriesDropsUserEntryWithoutVisibleTextBlocks() {
        let tool = ClaudeToolCallBlock(
            toolUseId: "tool-1",
            parentToolUseId: nil,
            name: "Read",
            input: #"{"file_path":"README.md"}"#,
            status: .running,
            resultText: nil
        )
        let entry = ClaudeConversationTimelineEntry(
            id: "user-tool-only",
            role: .user,
            blocks: [.toolCall(tool)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "user"
        )

        let messages = ClaudeTimelineMessageMapper.mapEntries([entry])

        XCTAssertTrue(messages.isEmpty)
    }

    func testMapEntriesKeepsUserEntryWithVisibleText() {
        let entry = ClaudeConversationTimelineEntry(
            id: "user-text",
            role: .user,
            blocks: [.text("Please ship this fix.")],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "user_prompt_command"
        )

        let messages = ClaudeTimelineMessageMapper.mapEntries([entry])

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.role, .user)
        XCTAssertEqual(messages.first?.content, "Please ship this fix.")
    }

    func testMapEntriesMapsToolStatusInputAndOutput() {
        let tool = ClaudeToolCallBlock(
            toolUseId: "tool-status-1",
            parentToolUseId: nil,
            name: "Bash",
            input: #"{"command":"swift test"}"#,
            status: .failed,
            resultText: "exit code 1"
        )
        let entry = ClaudeConversationTimelineEntry(
            id: "assistant-tool",
            role: .assistant,
            blocks: [.toolCall(tool)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "assistant"
        )

        let messages = ClaudeTimelineMessageMapper.mapEntries([entry])
        XCTAssertEqual(messages.count, 1)

        guard let blocks = messages.first?.parsedContent,
              blocks.count == 1,
              case .toolUse(let mappedTool) = blocks[0] else {
            XCTFail("Expected one mapped tool_use block")
            return
        }

        XCTAssertEqual(mappedTool.toolUseId, "tool-status-1")
        XCTAssertEqual(mappedTool.status, .failed)
        XCTAssertEqual(mappedTool.input, #"{"command":"swift test"}"#)
        XCTAssertEqual(mappedTool.output, "exit code 1")
    }

    func testMapEntriesMapsSubAgentStatusResultAndChildToolStatus() {
        let subAgent = ClaudeSubAgentBlock(
            parentToolUseId: "task-status-1",
            subagentType: "Explore",
            description: "Inspect mapper behavior",
            tools: [
                ClaudeToolCallBlock(
                    toolUseId: "child-status-1",
                    parentToolUseId: "task-status-1",
                    name: "Read",
                    input: #"{"file_path":"SessionDetailMessageMapper.swift"}"#,
                    status: .completed,
                    resultText: "loaded 420 lines"
                ),
                ClaudeToolCallBlock(
                    toolUseId: "child-status-2",
                    parentToolUseId: "task-status-1",
                    name: "Grep",
                    input: #"{"pattern":"mergedStatus"}"#,
                    status: .running,
                    resultText: nil
                ),
            ],
            status: .running,
            result: "Scanning status merge behavior"
        )
        let entry = ClaudeConversationTimelineEntry(
            id: "assistant-subagent",
            role: .assistant,
            blocks: [.subAgent(subAgent)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "assistant"
        )

        let messages = ClaudeTimelineMessageMapper.mapEntries([entry])
        XCTAssertEqual(messages.count, 1)

        guard let blocks = messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one mapped sub-agent block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task-status-1")
        XCTAssertEqual(activity.status, .running)
        XCTAssertEqual(activity.result, "Scanning status merge behavior")
        XCTAssertEqual(activity.tools.count, 2)
        XCTAssertEqual(activity.tools.map(\.status), [.completed, .running])
    }
}
