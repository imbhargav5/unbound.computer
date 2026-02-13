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
    var statusForTool: (SessionToolUse) -> ToolCallVisualStatus = { _ in .completed }

    @State private var isExpanded: Bool

    init(
        activity: SessionSubAgentActivity,
        defaultExpanded: Bool = false,
        showToolStatusLabels: Bool = false,
        statusForTool: @escaping (SessionToolUse) -> ToolCallVisualStatus = { _ in .completed }
    ) {
        self.activity = activity
        self.defaultExpanded = defaultExpanded
        self.showToolStatusLabels = showToolStatusLabels
        self.statusForTool = statusForTool
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                ForEach(activity.tools) { tool in
                    ToolCallView(
                        tool: tool,
                        status: statusForTool(tool),
                        showStatusLabel: showToolStatusLabels,
                        maxSummaryLines: 2
                    )
                }
            }
            .padding(.top, AppTheme.spacingXS)
        } label: {
            HStack(spacing: AppTheme.spacingS) {
                Image(systemName: activity.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.displayName)
                        .font(Typography.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    if !activity.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(activity.description)
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Text("\(activity.tools.count)")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .tint(AppTheme.textSecondary)
        .padding(.horizontal, AppTheme.spacingS + 2)
        .padding(.vertical, AppTheme.spacingXS + 2)
        .background(AppTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
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
                summary: "Read SessionMessagePayloadParser.swift"
            ),
            SessionToolUse(
                toolUseId: "tool-2",
                parentToolUseId: "task-1",
                toolName: "Write",
                summary: "Write parser-behavior-matrix.md"
            ),
            SessionToolUse(
                toolUseId: "tool-3",
                parentToolUseId: "task-1",
                toolName: "Bash",
                summary: "xcodebuild -project apps/ios/unbound-ios.xcodeproj -scheme unbound-ios"
            ),
        ]
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
                summary: "Read SessionDetailMessageMapper.swift"
            ),
            SessionToolUse(
                toolUseId: "tool-7",
                parentToolUseId: "task-3",
                toolName: "Bash",
                summary: "xcodebuild -project apps/ios/unbound-ios.xcodeproj -scheme unbound-ios"
            ),
        ]
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
                summary: "Grep payload wrappers across fixtures"
            ),
            SessionToolUse(
                toolUseId: "tool-5",
                parentToolUseId: "task-2",
                toolName: "Read",
                summary: "Read SessionDetailMessageMapper.swift"
            ),
        ]
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
