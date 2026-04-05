import XCTest

@testable import unbound_macos

final class ParallelAgentsSummaryModelTests: XCTestCase {
    func testAllRunningUsesRunningTitleAndTrackOnlyRing() {
        let activities = [
            makeActivity(id: "task-1", type: "Explore", status: .running),
            makeActivity(id: "task-2", type: "Explore", status: .running),
            makeActivity(id: "task-3", type: "Explore", status: .running),
        ]

        let summary = ParallelAgentsSummaryModel.build(for: activities.map(ParallelAgentItem.init(activity:)))

        XCTAssertEqual(summary.title, "Running 3 Explore agents")
        XCTAssertEqual(summary.ringState, .trackOnly)
    }

    func testPartialCompletionUsesAmberPartialRing() {
        let activities = [
            makeActivity(id: "task-1", type: "Explore", status: .completed),
            makeActivity(id: "task-2", type: "Explore", status: .running),
            makeActivity(id: "task-3", type: "Explore", status: .running),
        ]

        let summary = ParallelAgentsSummaryModel.build(for: activities.map(ParallelAgentItem.init(activity:)))

        XCTAssertEqual(summary.title, "1 of 3 Explore agents finished")
        XCTAssertEqual(summary.ringState, .partial(1.0 / 3.0))
    }

    func testAllCompletedUsesCompletedTitleAndGreenRing() {
        let activities = [
            makeActivity(id: "task-1", type: "Explore", status: .completed),
            makeActivity(id: "task-2", type: "Explore", status: .completed),
            makeActivity(id: "task-3", type: "Explore", status: .completed),
        ]

        let summary = ParallelAgentsSummaryModel.build(for: activities.map(ParallelAgentItem.init(activity:)))

        XCTAssertEqual(summary.title, "3 Explore agents finished")
        XCTAssertEqual(summary.ringState, .complete)
    }

    func testMixedTypesOmitsTypeLabel() {
        let activities = [
            makeActivity(id: "task-1", type: "Explore", status: .completed),
            makeActivity(id: "task-2", type: "Plan", status: .running),
            makeActivity(id: "task-3", type: "Bash", status: .running),
        ]

        let summary = ParallelAgentsSummaryModel.build(for: activities.map(ParallelAgentItem.init(activity:)))

        XCTAssertEqual(summary.title, "1 of 3 agents finished")
    }

    private func makeActivity(id: String, type: String, status: ToolStatus) -> SubAgentActivity {
        SubAgentActivity(
            parentToolUseId: id,
            subagentType: type,
            description: "Task",
            tools: [],
            status: status
        )
    }
}
