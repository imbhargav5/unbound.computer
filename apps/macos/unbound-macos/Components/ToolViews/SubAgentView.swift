//
//  SubAgentView.swift
//  unbound-macos
//
//  Unified sub-agent surface for live and historical states.
//

import SwiftUI

private enum SubAgentPayload {
    case active(ActiveSubAgent)
    case historical(SubAgentActivity)
}

struct SubAgentView: View {
    private let payload: SubAgentPayload
    private let initiallyExpanded: Bool

    init(activeSubAgent: ActiveSubAgent, initiallyExpanded: Bool = true) {
        self.payload = .active(activeSubAgent)
        self.initiallyExpanded = initiallyExpanded
    }

    init(activity: SubAgentActivity, initiallyExpanded: Bool = false) {
        self.payload = .historical(activity)
        self.initiallyExpanded = initiallyExpanded
    }

    var body: some View {
        switch payload {
        case .active(let subAgent):
            AgentCardView(subAgent: subAgent, initiallyExpanded: initiallyExpanded)

        case .historical(let activity):
            HistoricalAgentCardView(activity: activity, initiallyExpanded: initiallyExpanded)
        }
    }
}

private enum SubAgentPreviewData {
    static let activeRunning = ActiveSubAgent(
        id: "active-task-1",
        subagentType: "Plan",
        description: "Defining parser + renderer contracts",
        childTools: [
            ActiveTool(id: "active-tool-1", name: "Read", inputPreview: "SessionLiveState.swift", status: .completed),
            ActiveTool(id: "active-tool-2", name: "Write", inputPreview: "parser-contract.md", status: .running),
            ActiveTool(id: "active-tool-3", name: "Bash", inputPreview: "xcodebuild -project apps/macos/unbound-macos.xcodeproj", status: .completed),
        ],
        status: .running
    )

    static let activeCompleted = ActiveSubAgent(
        id: "active-task-3",
        subagentType: "Bash",
        description: "Compiled and validated parser matrix coverage",
        childTools: [
            ActiveTool(id: "active-tool-6", name: "Read", inputPreview: "SessionLiveState.swift", status: .completed),
            ActiveTool(id: "active-tool-7", name: "Bash", inputPreview: "xcodebuild -project apps/macos/unbound-macos.xcodeproj", status: .completed),
        ],
        status: .completed
    )

    static let activeFailed = ActiveSubAgent(
        id: "active-task-2",
        subagentType: "Explore",
        description: "Validating malformed payload deterministic fallback",
        childTools: [
            ActiveTool(id: "active-tool-4", name: "Grep", inputPreview: "raw_json", status: .completed),
            ActiveTool(id: "active-tool-5", name: "Read", inputPreview: "ClaudeMessageParser.swift", status: .failed),
        ],
        status: .failed
    )

    static let historicalCompleted = SubAgentActivity(
        parentToolUseId: "hist-task-1",
        subagentType: "Explore",
        description: "Validated malformed payload fallback behavior",
        tools: [
            ToolUse(toolUseId: "hist-tool-1", parentToolUseId: "hist-task-1", toolName: "Grep", input: "{\"pattern\":\"tool_result\"}", status: .completed),
            ToolUse(toolUseId: "hist-tool-2", parentToolUseId: "hist-task-1", toolName: "Read", input: "{\"file_path\":\"SessionMessagePayloadParser.swift\"}", status: .completed),
        ],
        status: .completed
    )

    static let historicalCompact = SubAgentActivity(
        parentToolUseId: "hist-task-2",
        subagentType: "general-purpose",
        description: "Summarized contract deltas",
        tools: [],
        status: .completed
    )
}

#Preview("SubAgent Wrapper Variants") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        SubAgentView(activeSubAgent: SubAgentPreviewData.activeRunning)
        SubAgentView(activeSubAgent: SubAgentPreviewData.activeCompleted)
        SubAgentView(activeSubAgent: SubAgentPreviewData.activeFailed)
        SubAgentView(activeSubAgent: SubAgentPreviewData.activeCompleted, initiallyExpanded: false)
        SubAgentView(activity: SubAgentPreviewData.historicalCompleted)
        SubAgentView(activity: SubAgentPreviewData.historicalCompact)
        SubAgentView(activity: SubAgentPreviewData.historicalCompleted, initiallyExpanded: true)
    }
    .frame(width: 540)
    .padding()
}
