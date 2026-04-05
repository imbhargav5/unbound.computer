import XCTest

@testable import unbound_macos

final class ChatTimelineSnapshotEngineTests: XCTestCase {
    func testBuildIsDeterministicForSameInput() async {
        let engine = ChatTimelineSnapshotEngine()
        let messages = makeMessages()
        let input = ChatTimelineSnapshotEngine.Input(
            messages: messages,
            toolHistory: [],
            activeSubAgents: [],
            activeTools: [],
            streamingAssistantMessage: nil
        )

        let first = await engine.build(input)
        let second = await engine.build(input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.revision, second.revision)
        XCTAssertEqual(first.rows.count, 2)
    }

    func testBuildKeepsUnchangedRowsStableWhenSingleMessageChanges() async {
        let engine = ChatTimelineSnapshotEngine()

        let baselineMessages = makeMessages()
        let baselineInput = ChatTimelineSnapshotEngine.Input(
            messages: baselineMessages,
            toolHistory: [],
            activeSubAgents: [],
            activeTools: [],
            streamingAssistantMessage: nil
        )

        let baseline = await engine.build(baselineInput)

        var changedMessages = baselineMessages
        changedMessages[1] = ChatMessage(
            id: changedMessages[1].id,
            role: changedMessages[1].role,
            content: [.text(TextContent(id: changedMessages[1].content[0].id, text: "Updated answer"))],
            timestamp: changedMessages[1].timestamp,
            isStreaming: changedMessages[1].isStreaming,
            sequenceNumber: changedMessages[1].sequenceNumber
        )

        let changedInput = ChatTimelineSnapshotEngine.Input(
            messages: changedMessages,
            toolHistory: [],
            activeSubAgents: [],
            activeTools: [],
            streamingAssistantMessage: nil
        )

        let changed = await engine.build(changedInput)

        XCTAssertEqual(changed.rows.count, baseline.rows.count)
        XCTAssertEqual(changed.rows[0], baseline.rows[0])
        XCTAssertNotEqual(changed.rows[1].renderKey, baseline.rows[1].renderKey)
    }

    func testBuildDetectsTextChangeWhenLengthIsUnchanged() async {
        let engine = ChatTimelineSnapshotEngine()

        let messageID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let textID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

        let baseline = ChatMessage(
            id: messageID,
            role: .assistant,
            content: [.text(TextContent(id: textID, text: "abc"))],
            timestamp: Date(timeIntervalSince1970: 10),
            isStreaming: false,
            sequenceNumber: 1
        )

        let updated = ChatMessage(
            id: messageID,
            role: .assistant,
            content: [.text(TextContent(id: textID, text: "xyz"))], // same length, different content
            timestamp: Date(timeIntervalSince1970: 10),
            isStreaming: false,
            sequenceNumber: 1
        )

        let first = await engine.build(
            .init(
                messages: [baseline],
                toolHistory: [],
                activeSubAgents: [],
                activeTools: [],
                streamingAssistantMessage: nil
            )
        )
        let second = await engine.build(
            .init(
                messages: [updated],
                toolHistory: [],
                activeSubAgents: [],
                activeTools: [],
                streamingAssistantMessage: nil
            )
        )

        XCTAssertEqual(first.rows.count, 1)
        XCTAssertEqual(second.rows.count, 1)
        XCTAssertNotEqual(first.rows[0].renderKey, second.rows[0].renderKey)
        XCTAssertNotEqual(first.revision, second.revision)
    }

    func testBuildDetectsActiveToolOutputChangeWithSameLength() async {
        let engine = ChatTimelineSnapshotEngine()
        let messages = makeMessages()

        let baselineTool = ActiveTool(
            id: "tool-use-1",
            name: "Bash",
            inputPreview: "echo",
            status: .running,
            output: "abc"
        )
        let updatedTool = ActiveTool(
            id: "tool-use-1",
            name: "Bash",
            inputPreview: "echo",
            status: .running,
            output: "xyz" // same length, different content
        )

        let first = await engine.build(
            .init(
                messages: messages,
                toolHistory: [],
                activeSubAgents: [],
                activeTools: [baselineTool],
                streamingAssistantMessage: nil
            )
        )
        let second = await engine.build(
            .init(
                messages: messages,
                toolHistory: [],
                activeSubAgents: [],
                activeTools: [updatedTool],
                streamingAssistantMessage: nil
            )
        )

        XCTAssertNotEqual(first.revision, second.revision)
        XCTAssertEqual(second.activeTools.first?.output, "xyz")
    }

    func testBlockKindGroupingOrder() async {
        let engine = ChatTimelineSnapshotEngine()

        let tool1 = ToolUse(toolUseId: "tool-1", toolName: "Read", input: "{\"file_path\":\"README.md\"}", status: .completed)
        let tool2 = ToolUse(toolUseId: "tool-2", toolName: "Read", input: "{\"file_path\":\"App.swift\"}", status: .completed)
        let subAgent1 = SubAgentActivity(parentToolUseId: "task-1", subagentType: "Explore", description: "Explore A", status: .running)
        let subAgent2 = SubAgentActivity(parentToolUseId: "task-2", subagentType: "Plan", description: "Plan B", status: .completed)

        let content: [MessageContent] = [
            .text(TextContent(text: "Intro")),
            .toolUse(tool1),
            .toolUse(tool2),
            .subAgentActivity(subAgent1),
            .subAgentActivity(subAgent2),
            .text(TextContent(text: "Summary")),
        ]

        let message = ChatMessage(role: .assistant, content: content, sequenceNumber: 1)
        let input = ChatTimelineSnapshotEngine.Input(
            messages: [message],
            toolHistory: [],
            activeSubAgents: [],
            activeTools: [],
            streamingAssistantMessage: nil
        )

        let snapshot = await engine.build(input)

        let snapshotKinds = snapshot.rows.first?.blocks.map { block -> String in
            switch block {
            case .content:
                return "content"
            case .standaloneTools:
                return "standaloneTools"
            case .parallelAgents:
                return "parallelAgents"
            }
        }

        XCTAssertEqual(snapshotKinds, ["content", "standaloneTools", "parallelAgents", "content"])
    }

    private func makeMessages() -> [ChatMessage] {
        [
            ChatMessage(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                role: .user,
                content: [.text(TextContent(id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!, text: "Question"))],
                timestamp: Date(timeIntervalSince1970: 1),
                isStreaming: false,
                sequenceNumber: 1
            ),
            ChatMessage(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                role: .assistant,
                content: [.text(TextContent(id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!, text: "Answer"))],
                timestamp: Date(timeIntervalSince1970: 2),
                isStreaming: false,
                sequenceNumber: 2
            ),
        ]
    }
}
