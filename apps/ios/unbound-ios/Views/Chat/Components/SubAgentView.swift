//
//  SubAgentView.swift
//  unbound-ios
//
//  Reusable sub-agent activity component for chat/session surfaces.
//

import SwiftUI

struct SubAgentView: View {
    let activity: SessionSubAgentActivity
    var defaultExpanded: Bool = false
    var showToolStatusLabels: Bool = false
    var statusForTool: (SessionToolUse) -> ToolCallVisualStatus = { tool in
        switch tool.status {
        case .running:
            return .running
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }

    init(
        activity: SessionSubAgentActivity,
        defaultExpanded: Bool = false,
        showToolStatusLabels: Bool = false,
        statusForTool: @escaping (SessionToolUse) -> ToolCallVisualStatus = { tool in
            switch tool.status {
            case .running:
                return .running
            case .completed:
                return .completed
            case .failed:
                return .failed
            }
        }
    ) {
        self.activity = activity
        self.defaultExpanded = defaultExpanded
        self.showToolStatusLabels = showToolStatusLabels
        self.statusForTool = statusForTool
    }

    var body: some View {
        ParallelAgentsView(
            activities: [resolvedActivity],
            defaultRowExpanded: defaultExpanded
        )
    }

    private var resolvedActivity: SessionSubAgentActivity {
        let mappedTools = activity.tools.map { tool in
            SessionToolUse(
                id: tool.id,
                toolUseId: tool.toolUseId,
                parentToolUseId: tool.parentToolUseId,
                toolName: tool.toolName,
                summary: tool.summary,
                status: mapStatus(statusForTool(tool)),
                input: tool.input,
                output: tool.output
            )
        }

        let resolvedStatus: SessionToolStatus
        if mappedTools.contains(where: { $0.status == .running }) {
            resolvedStatus = .running
        } else if mappedTools.contains(where: { $0.status == .failed }) {
            resolvedStatus = .failed
        } else {
            resolvedStatus = activity.status
        }

        return SessionSubAgentActivity(
            id: activity.id,
            parentToolUseId: activity.parentToolUseId,
            subagentType: activity.subagentType,
            description: activity.description,
            tools: mappedTools,
            status: resolvedStatus,
            result: activity.result
        )
    }

    private func mapStatus(_ status: ToolCallVisualStatus) -> SessionToolStatus {
        switch status {
        case .running:
            return .running
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }
}

private enum SubAgentPreviewData {
    static let runningActivity = SessionSubAgentActivity(
        parentToolUseId: "task-1",
        subagentType: "Plan",
        description: "Split parser and mapper contracts into explicit states",
        tools: [
            SessionToolUse(
                toolUseId: "tool-1",
                parentToolUseId: "task-1",
                toolName: "Read",
                summary: "Read SessionMessagePayloadParser.swift",
                status: .completed,
                input: "{\"file_path\":\"SessionMessagePayloadParser.swift\"}",
                output: "Parser behavior matrix captured."
            ),
            SessionToolUse(
                toolUseId: "tool-2",
                parentToolUseId: "task-1",
                toolName: "Write",
                summary: "Write parser-behavior-matrix.md",
                status: .running,
                input: "{\"file_path\":\"docs/parser-behavior-matrix.md\"}"
            ),
            SessionToolUse(
                toolUseId: "tool-3",
                parentToolUseId: "task-1",
                toolName: "Bash",
                summary: "xcodebuild -project apps/ios/unbound-ios.xcodeproj -scheme unbound-ios",
                status: .completed,
                input: "{\"command\":\"xcodebuild -project apps/ios/unbound-ios.xcodeproj -scheme unbound-ios\"}",
                output: "BUILD SUCCEEDED"
            ),
        ],
        status: .running,
        result: "Drafting grouped rendering contract updates."
    )

    static let completedActivity = SessionSubAgentActivity(
        parentToolUseId: "task-3",
        subagentType: "Bash",
        description: "Compiled and validated parser fixtures against iOS simulator build",
        tools: [
            SessionToolUse(
                toolUseId: "tool-6",
                parentToolUseId: "task-3",
                toolName: "Read",
                summary: "Read SessionDetailMessageMapper.swift",
                status: .completed,
                input: "{\"file_path\":\"SessionDetailMessageMapper.swift\"}",
                output: "Loaded 420 lines."
            ),
            SessionToolUse(
                toolUseId: "tool-7",
                parentToolUseId: "task-3",
                toolName: "Bash",
                summary: "xcodebuild -project apps/ios/unbound-ios.xcodeproj -scheme unbound-ios",
                status: .completed,
                input: "{\"command\":\"xcodebuild -project apps/ios/unbound-ios.xcodeproj -scheme unbound-ios\"}",
                output: "All parser tests passed."
            ),
        ],
        status: .completed,
        result: "Parser + mapper parity checks completed."
    )

    static let failedActivity = SessionSubAgentActivity(
        parentToolUseId: "task-2",
        subagentType: "Explore",
        description: "Protocol artifacts stripped from visible transcript",
        tools: [
            SessionToolUse(
                toolUseId: "tool-4",
                parentToolUseId: "task-2",
                toolName: "Grep",
                summary: "Grep payload wrappers across fixtures",
                status: .failed,
                input: "{\"pattern\":\"raw_json\"}",
                output: "grep: malformed regex"
            ),
            SessionToolUse(
                toolUseId: "tool-5",
                parentToolUseId: "task-2",
                toolName: "Read",
                summary: "Read SessionDetailMessageMapper.swift",
                status: .completed,
                input: "{\"file_path\":\"SessionDetailMessageMapper.swift\"}",
                output: "Merged status rules reviewed."
            ),
        ],
        status: .failed,
        result: "Validation failed while matching malformed wrapper edge cases."
    )

    static let idleActivity = SessionSubAgentActivity(
        parentToolUseId: "task-4",
        subagentType: "general-purpose",
        description: "Waiting for next parsing directive",
        tools: []
    )

    enum ToolStatusProfile {
        case runningWrite
        case failedGrep
        case allCompleted
        case mixed
    }

    static let scenarios: [SubAgentPreviewScenario] = [
        SubAgentPreviewScenario(
            id: "running-expanded",
            title: "Running expanded",
            activity: runningActivity,
            defaultExpanded: true,
            showToolStatusLabels: true,
            statusProfile: .runningWrite
        ),
        SubAgentPreviewScenario(
            id: "completed-collapsed",
            title: "Completed collapsed",
            activity: completedActivity,
            defaultExpanded: false,
            showToolStatusLabels: false,
            statusProfile: .allCompleted
        ),
        SubAgentPreviewScenario(
            id: "failed-expanded",
            title: "Failed expanded",
            activity: failedActivity,
            defaultExpanded: true,
            showToolStatusLabels: true,
            statusProfile: .failedGrep
        ),
        SubAgentPreviewScenario(
            id: "idle-empty",
            title: "Idle empty tool list",
            activity: idleActivity,
            defaultExpanded: false,
            showToolStatusLabels: false,
            statusProfile: .allCompleted
        ),
    ]

    static func status(for tool: SessionToolUse, profile: ToolStatusProfile) -> ToolCallVisualStatus {
        switch profile {
        case .runningWrite:
            if tool.toolName == "Write" {
                return .running
            }
            return .completed

        case .failedGrep:
            if tool.toolName == "Grep" {
                return .failed
            }
            return .completed

        case .allCompleted:
            return .completed

        case .mixed:
            if tool.toolName == "Write" || tool.toolName == "Bash" {
                return .running
            }
            if tool.toolName == "Grep" {
                return .failed
            }
            return .completed
        }
    }
}

private struct SubAgentPreviewScenario: Identifiable {
    let id: String
    let title: String
    let activity: SessionSubAgentActivity
    let defaultExpanded: Bool
    let showToolStatusLabels: Bool
    let statusProfile: SubAgentPreviewData.ToolStatusProfile
}

#Preview("Sub Agent Variants") {
    VStack(alignment: .leading, spacing: AppTheme.spacingS) {
        ForEach(SubAgentPreviewData.scenarios) { scenario in
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.title)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                SubAgentView(
                    activity: scenario.activity,
                    defaultExpanded: scenario.defaultExpanded,
                    showToolStatusLabels: scenario.showToolStatusLabels,
                    statusForTool: { tool in
                        SubAgentPreviewData.status(for: tool, profile: scenario.statusProfile)
                    }
                )
            }
        }
    }
    .frame(maxWidth: 560, alignment: .leading)
    .padding()
    .background(AppTheme.backgroundPrimary)
}
