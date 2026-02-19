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

    func testMapEntriesKeepsAssistantTextAlongsideStandaloneToolUse() throws {
        let entry = ClaudeConversationTimelineEntry(
            id: "assistant-text-and-tool",
            role: .assistant,
            blocks: [
                .text("I'll create 3 explore agents in parallel."),
                .toolCall(makeTool(toolUseId: "tool-standalone", parentToolUseId: nil, name: "Read")),
            ],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "assistant"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])

        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first)
        XCTAssertEqual(message.textContent, "I'll create 3 explore agents in parallel.")
        let toolUses = message.content.compactMap { content -> ToolUse? in
            guard case .toolUse(let toolUse) = content else { return nil }
            return toolUse
        }
        XCTAssertEqual(toolUses.map(\.toolUseId), ["tool-standalone"])
    }

    func testMapEntriesMapsTodoWriteToolToTodoList() throws {
        let todoInput = #"{"todos":[{"content":"Ship parser fix","status":"pending"},{"content":"Run tests","status":"in_progress"},{"content":"Write summary","status":"completed"}]}"#
        let todoTool = ClaudeToolCallBlock(
            toolUseId: "todo-1",
            parentToolUseId: nil,
            name: "TodoWrite",
            input: todoInput,
            status: .completed,
            resultText: nil
        )
        let entry = ClaudeConversationTimelineEntry(
            id: "assistant-todo",
            role: .assistant,
            blocks: [.toolCall(todoTool)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "assistant"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])
        let message = try XCTUnwrap(messages.first)

        let todoLists = message.content.compactMap { content -> TodoList? in
            guard case .todoList(let value) = content else { return nil }
            return value
        }
        XCTAssertEqual(todoLists.count, 1)
        XCTAssertEqual(todoLists[0].items.map(\.content), ["Ship parser fix", "Run tests", "Write summary"])
        XCTAssertEqual(todoLists[0].items.map(\.status), [.pending, .inProgress, .completed])

        let toolUses = message.content.compactMap { content -> ToolUse? in
            guard case .toolUse(let value) = content else { return nil }
            return value
        }
        XCTAssertTrue(toolUses.isEmpty)
    }

    func testMapEntriesTodoWriteMalformedInputFallsBackToGenericToolUse() throws {
        let malformedTodoTool = ClaudeToolCallBlock(
            toolUseId: "todo-bad",
            parentToolUseId: nil,
            name: "TodoWrite",
            input: "{this is invalid json}",
            status: .running,
            resultText: nil
        )
        let entry = ClaudeConversationTimelineEntry(
            id: "assistant-todo-bad",
            role: .assistant,
            blocks: [.toolCall(malformedTodoTool)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "assistant"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])
        let message = try XCTUnwrap(messages.first)

        let toolUses = message.content.compactMap { content -> ToolUse? in
            guard case .toolUse(let value) = content else { return nil }
            return value
        }
        XCTAssertEqual(toolUses.count, 1)
        XCTAssertEqual(toolUses.first?.toolName, "TodoWrite")

        let todoLists = message.content.compactMap { content -> TodoList? in
            guard case .todoList(let value) = content else { return nil }
            return value
        }
        XCTAssertTrue(todoLists.isEmpty)
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
