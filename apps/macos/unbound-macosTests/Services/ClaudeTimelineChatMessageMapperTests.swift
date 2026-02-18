import ClaudeConversationTimeline
import XCTest

@testable import unbound_macos

final class ClaudeTimelineChatMessageMapperTests: XCTestCase {
    func testMapEntriesDropsUserEntryWithProtocolArtifactOnlyText() {
        let entry = ClaudeConversationTimelineEntry(
            id: "user-envelope",
            role: .user,
            blocks: [.text(#"{"type":"assistant","message":{"content":[{"type":"text","text":"artifact"}]}}"#)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "user_prompt_command"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])

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

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])

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

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.role, .user)
        XCTAssertEqual(messages.first?.textContent, "Please ship this fix.")
    }

    func testMapEntriesGroupsChildToolIntoLaterTaskSubAgent() {
        let childEntry = ClaudeConversationTimelineEntry(
            id: "assistant-child",
            role: .assistant,
            blocks: [.toolCall(makeTool(toolUseId: "tool-1", parentToolUseId: "task-1", name: "Read"))],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "assistant"
        )
        let taskEntry = ClaudeConversationTimelineEntry(
            id: "assistant-task",
            role: .assistant,
            blocks: [.subAgent(makeSubAgent(parentToolUseId: "task-1", description: "Search codebase"))],
            createdAt: Date(timeIntervalSince1970: 2),
            sequence: 2,
            sourceType: "assistant"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([childEntry, taskEntry])

        XCTAssertEqual(messages.count, 1)
        let subAgent = firstSubAgent(in: messages)
        XCTAssertNotNil(subAgent)
        XCTAssertEqual(subAgent?.parentToolUseId, "task-1")
        XCTAssertEqual(subAgent?.tools.compactMap(\.toolUseId), ["tool-1"])
    }

    func testMapEntriesKeepsTextWhenGroupingChildToolIntoSubAgent() {
        let taskEntry = ClaudeConversationTimelineEntry(
            id: "assistant-task",
            role: .assistant,
            blocks: [.subAgent(makeSubAgent(parentToolUseId: "task-2", description: "Plan changes"))],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "assistant"
        )
        let childWithTextEntry = ClaudeConversationTimelineEntry(
            id: "assistant-child-with-text",
            role: .assistant,
            blocks: [
                .text("Working on it"),
                .toolCall(makeTool(toolUseId: "tool-2", parentToolUseId: "task-2", name: "Grep")),
            ],
            createdAt: Date(timeIntervalSince1970: 2),
            sequence: 2,
            sourceType: "assistant"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([taskEntry, childWithTextEntry])

        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.contains(where: { $0.textContent == "Working on it" }))
        let subAgent = firstSubAgent(in: messages)
        XCTAssertEqual(subAgent?.tools.compactMap(\.toolUseId), ["tool-2"])
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

    private func makeTool(toolUseId: String, parentToolUseId: String?, name: String) -> ClaudeToolCallBlock {
        ClaudeToolCallBlock(
            toolUseId: toolUseId,
            parentToolUseId: parentToolUseId,
            name: name,
            input: nil,
            status: .running,
            resultText: nil
        )
    }

    private func makeSubAgent(parentToolUseId: String, description: String) -> ClaudeSubAgentBlock {
        ClaudeSubAgentBlock(
            parentToolUseId: parentToolUseId,
            subagentType: "Explore",
            description: description,
            tools: [],
            status: .running,
            result: nil
        )
    }
}
