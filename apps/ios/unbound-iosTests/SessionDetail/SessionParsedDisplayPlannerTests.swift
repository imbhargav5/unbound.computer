import XCTest

@testable import unbound_ios

final class SessionParsedDisplayPlannerTests: XCTestCase {
    func testDisplayBlocksGroupsConsecutiveSubAgentActivitiesIntoSingleParallelGroup() {
        let blocks: [SessionContentBlock] = [
            .text("Intro"),
            .subAgentActivity(makeActivity(id: "task-1")),
            .subAgentActivity(makeActivity(id: "task-2")),
            .subAgentActivity(makeActivity(id: "task-3")),
            .error("Done"),
        ]

        let displayBlocks = SessionParsedDisplayPlanner.displayBlocks(from: blocks)
        XCTAssertEqual(displayBlocks.count, 3)

        guard case .block(.text("Intro")) = displayBlocks[0] else {
            XCTFail("Expected first block to remain text")
            return
        }

        guard case .parallelSubAgentGroup(let activities) = displayBlocks[1] else {
            XCTFail("Expected middle block to be grouped sub-agent activities")
            return
        }
        XCTAssertEqual(activities.map(\.parentToolUseId), ["task-1", "task-2", "task-3"])

        guard case .block(.error("Done")) = displayBlocks[2] else {
            XCTFail("Expected last block to remain error content")
            return
        }
    }

    func testDisplayBlocksPreservesStandaloneToolGroupingAlongsideParallelSubAgentGrouping() {
        let blocks: [SessionContentBlock] = [
            .toolUse(makeTool(id: "tool-1", parentId: nil)),
            .toolUse(makeTool(id: "tool-2", parentId: nil)),
            .subAgentActivity(makeActivity(id: "task-1")),
            .subAgentActivity(makeActivity(id: "task-2")),
            .toolUse(makeTool(id: "tool-3", parentId: nil)),
            .text("Summary"),
        ]

        let displayBlocks = SessionParsedDisplayPlanner.displayBlocks(from: blocks)
        XCTAssertEqual(displayBlocks.count, 4)

        guard case .standaloneToolUseGroup(let firstGroup) = displayBlocks[0] else {
            XCTFail("Expected first block to be grouped standalone tools")
            return
        }
        XCTAssertEqual(firstGroup.compactMap(\.toolUseId), ["tool-1", "tool-2"])

        guard case .parallelSubAgentGroup(let subAgents) = displayBlocks[1] else {
            XCTFail("Expected second block to be grouped sub-agent activities")
            return
        }
        XCTAssertEqual(subAgents.map(\.parentToolUseId), ["task-1", "task-2"])

        guard case .standaloneToolUseGroup(let secondGroup) = displayBlocks[2] else {
            XCTFail("Expected third block to be grouped standalone tools")
            return
        }
        XCTAssertEqual(secondGroup.compactMap(\.toolUseId), ["tool-3"])

        guard case .block(.text("Summary")) = displayBlocks[3] else {
            XCTFail("Expected final block to remain text")
            return
        }
    }

    private func makeActivity(id: String) -> SessionSubAgentActivity {
        SessionSubAgentActivity(
            parentToolUseId: id,
            subagentType: "Explore",
            description: "Inspect \(id)",
            status: .running
        )
    }

    private func makeTool(id: String, parentId: String?) -> SessionToolUse {
        SessionToolUse(
            toolUseId: id,
            parentToolUseId: parentId,
            toolName: "Read",
            summary: "Read file",
            status: .completed
        )
    }
}
