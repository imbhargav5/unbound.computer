import XCTest

@testable import unbound_macos

final class ChatToolSurfaceDeduperTests: XCTestCase {
    func testSubAgentInMessageSuppressesActiveSubAgentCard() {
        let messages = [
            makeAssistantMessage(content: [
                .subAgentActivity(makeSubAgentActivity(parentToolUseId: "task_1")),
            ]),
        ]
        let activeSubAgents = [
            makeActiveSubAgent(id: "task_1"),
            makeActiveSubAgent(id: "task_2"),
        ]

        let state = ChatToolSurfaceDeduper.dedupe(
            messages: messages,
            toolHistory: [],
            activeSubAgents: activeSubAgents,
            activeTools: []
        )

        XCTAssertEqual(state.visibleActiveSubAgents.map(\.id), ["task_2"])
    }

    func testStandaloneToolInMessageSuppressesActiveToolCard() {
        let messages = [
            makeAssistantMessage(content: [
                .toolUse(makeToolUse(id: "tool_1")),
            ]),
        ]
        let activeTools = [
            makeActiveTool(id: "tool_1"),
            makeActiveTool(id: "tool_2"),
        ]

        let state = ChatToolSurfaceDeduper.dedupe(
            messages: messages,
            toolHistory: [],
            activeSubAgents: [],
            activeTools: activeTools
        )

        XCTAssertEqual(state.visibleActiveTools.map(\.id), ["tool_2"])
    }

    func testMessageSubAgentSuppressesDuplicateHistorySubAgentEntry() {
        let messages = [
            makeAssistantMessage(content: [
                .subAgentActivity(makeSubAgentActivity(parentToolUseId: "task_1", status: .completed)),
            ]),
        ]
        let history = [
            ToolHistoryEntry(
                tools: [],
                subAgent: makeActiveSubAgent(id: "task_1", status: .completed),
                afterMessageIndex: 0
            ),
            ToolHistoryEntry(
                tools: [],
                subAgent: makeActiveSubAgent(id: "task_2", status: .completed),
                afterMessageIndex: 0
            ),
        ]

        let state = ChatToolSurfaceDeduper.dedupe(
            messages: messages,
            toolHistory: history,
            activeSubAgents: [],
            activeTools: []
        )

        XCTAssertEqual(state.visibleToolHistory.count, 1)
        XCTAssertEqual(state.visibleToolHistory.first?.subAgent?.id, "task_2")
    }

    func testMessageToolSuppressesDuplicateHistoryToolButKeepsOthers() {
        let messages = [
            makeAssistantMessage(content: [
                .toolUse(makeToolUse(id: "tool_1", status: .completed)),
            ]),
        ]

        let retainedHistoryID = UUID()
        let droppedHistoryID = UUID()
        let history = [
            ToolHistoryEntry(
                id: retainedHistoryID,
                tools: [
                    makeActiveTool(id: "tool_1", status: .completed),
                    makeActiveTool(id: "tool_2", status: .completed),
                ],
                subAgent: nil,
                afterMessageIndex: 0
            ),
            ToolHistoryEntry(
                id: droppedHistoryID,
                tools: [makeActiveTool(id: "tool_1", status: .completed)],
                subAgent: nil,
                afterMessageIndex: 0
            ),
        ]

        let state = ChatToolSurfaceDeduper.dedupe(
            messages: messages,
            toolHistory: history,
            activeSubAgents: [],
            activeTools: []
        )

        XCTAssertEqual(state.visibleToolHistory.count, 1)
        XCTAssertEqual(state.visibleToolHistory.first?.id, retainedHistoryID)
        XCTAssertEqual(state.visibleToolHistory.first?.tools.map(\.id), ["tool_2"])
    }

    private func makeAssistantMessage(content: [MessageContent]) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: content,
            timestamp: Date(timeIntervalSince1970: 1),
            isStreaming: false,
            sequenceNumber: 1
        )
    }

    private func makeToolUse(id: String, status: ToolStatus = .running) -> ToolUse {
        ToolUse(
            toolUseId: id,
            toolName: "Read",
            input: #"{"file_path":"README.md"}"#,
            status: status
        )
    }

    private func makeSubAgentActivity(parentToolUseId: String, status: ToolStatus = .running) -> SubAgentActivity {
        SubAgentActivity(
            parentToolUseId: parentToolUseId,
            subagentType: "Explore",
            description: "Inspect files",
            tools: [],
            status: status,
            result: nil
        )
    }

    private func makeActiveTool(id: String, status: ToolStatus = .running) -> ActiveTool {
        ActiveTool(
            id: id,
            name: "Read",
            inputPreview: "README.md",
            status: status,
            output: nil
        )
    }

    private func makeActiveSubAgent(id: String, status: ToolStatus = .running) -> ActiveSubAgent {
        ActiveSubAgent(
            id: id,
            subagentType: "Explore",
            description: "Inspect files",
            childTools: [],
            status: status
        )
    }
}
