import XCTest

@testable import unbound_macos

final class ChatMessageRenderPlannerTests: XCTestCase {
    func testRenderBlocksGroupsConsecutiveSubAgentsIntoSingleParallelBlock() {
        let content: [MessageContent] = [
            .text(TextContent(text: "Intro")),
            .subAgentActivity(makeActivity(id: "task-1")),
            .subAgentActivity(makeActivity(id: "task-2")),
            .subAgentActivity(makeActivity(id: "task-3")),
            .error(ErrorContent(message: "done")),
        ]

        let blocks = ChatMessageRenderPlanner.renderBlocks(from: content, isUser: false)
        XCTAssertEqual(blocks.count, 3)

        guard case .content(.text(let textContent)) = blocks[0] else {
            XCTFail("Expected first block to remain text content")
            return
        }
        XCTAssertEqual(textContent.text, "Intro")

        guard case .parallelAgents(let activities) = blocks[1] else {
            XCTFail("Expected middle block to be grouped parallel agents")
            return
        }
        XCTAssertEqual(activities.map(\.parentToolUseId), ["task-1", "task-2", "task-3"])

        guard case .content(.error(let errorContent)) = blocks[2] else {
            XCTFail("Expected final block to remain error content")
            return
        }
        XCTAssertEqual(errorContent.message, "done")
    }

    func testRenderBlocksKeepsStandaloneToolsGroupedSeparatelyFromParallelAgents() {
        let content: [MessageContent] = [
            .toolUse(makeTool(id: "tool-1")),
            .toolUse(makeTool(id: "tool-2")),
            .subAgentActivity(makeActivity(id: "task-1")),
            .subAgentActivity(makeActivity(id: "task-2")),
            .toolUse(makeTool(id: "tool-3")),
            .text(TextContent(text: "Summary")),
        ]

        let blocks = ChatMessageRenderPlanner.renderBlocks(from: content, isUser: false)
        XCTAssertEqual(blocks.count, 4)

        guard case .standaloneTools(let firstTools) = blocks[0] else {
            XCTFail("Expected first block to be standalone tool group")
            return
        }
        XCTAssertEqual(firstTools.compactMap(\.toolUseId), ["tool-1", "tool-2"])

        guard case .parallelAgents(let activities) = blocks[1] else {
            XCTFail("Expected second block to be parallel agent group")
            return
        }
        XCTAssertEqual(activities.map(\.parentToolUseId), ["task-1", "task-2"])

        guard case .standaloneTools(let secondTools) = blocks[2] else {
            XCTFail("Expected third block to be standalone tool group")
            return
        }
        XCTAssertEqual(secondTools.compactMap(\.toolUseId), ["tool-3"])

        guard case .content(.text(let textContent)) = blocks[3] else {
            XCTFail("Expected final block to remain text content")
            return
        }
        XCTAssertEqual(textContent.text, "Summary")
    }

    private func makeTool(id: String) -> ToolUse {
        ToolUse(
            toolUseId: id,
            toolName: "Read",
            input: "{\"file_path\":\"README.md\"}",
            status: .completed
        )
    }

    private func makeActivity(id: String) -> SubAgentActivity {
        SubAgentActivity(
            parentToolUseId: id,
            subagentType: "Explore",
            description: "Inspect \(id)",
            status: .running
        )
    }
}
