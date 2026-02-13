//
//  StandaloneToolCallsView.swift
//  unbound-ios
//
//  Reusable standalone tool-call group component for chat/session surfaces.
//

import SwiftUI

struct StandaloneToolCallsView: View {
    let tools: [SessionToolUse]
    var defaultExpanded: Bool = false
    var showToolStatusLabels: Bool = false
    var statusForTool: (SessionToolUse) -> ToolCallVisualStatus = { _ in .completed }

    @State private var isExpanded: Bool

    init(
        tools: [SessionToolUse],
        defaultExpanded: Bool = false,
        showToolStatusLabels: Bool = false,
        statusForTool: @escaping (SessionToolUse) -> ToolCallVisualStatus = { _ in .completed }
    ) {
        self.tools = tools
        self.defaultExpanded = defaultExpanded
        self.showToolStatusLabels = showToolStatusLabels
        self.statusForTool = statusForTool
        _isExpanded = State(initialValue: defaultExpanded)
    }

    private var primaryTitle: String {
        if tools.count == 1, let tool = tools.first {
            return tool.summary
        }
        return "Tool Use Activity"
    }

    private var secondaryTitle: String {
        if tools.count == 1, let tool = tools.first {
            return tool.toolName
        }
        return "\(tools.count) tool calls"
    }

    var body: some View {
        if tools.count == 1, let tool = tools.first {
            ToolCallView(
                tool: tool,
                status: statusForTool(tool),
                showStatusLabel: showToolStatusLabels,
                maxSummaryLines: 2
            )
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    ForEach(tools) { tool in
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
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryTitle)
                            .font(Typography.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        Text(secondaryTitle)
                            .font(Typography.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text("\(tools.count)")
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
}

private enum StandaloneToolCallsPreviewData {
    static let singleRunning: [SessionToolUse] = [
        SessionToolUse(
            toolUseId: "single-1",
            toolName: "Bash",
            summary: "xcodebuild -project apps/ios/unbound-ios.xcodeproj"
        ),
    ]

    static let singleCompleted: [SessionToolUse] = [
        SessionToolUse(
            toolUseId: "single-2",
            toolName: "Read",
            summary: "Read SessionContentBlock.swift"
        ),
    ]

    static let singleFailed: [SessionToolUse] = [
        SessionToolUse(
            toolUseId: "single-3",
            toolName: "WebFetch",
            summary: "Fetch parser contract from docs endpoint and normalize wrapped payload content"
        ),
    ]

    static let multiMixed: [SessionToolUse] = [
        SessionToolUse(
            toolUseId: "multi-1",
            toolName: "Read",
            summary: "Read SessionDetailMessageMapper.swift"
        ),
        SessionToolUse(
            toolUseId: "multi-2",
            toolName: "Write",
            summary: "Write SessionDetail behavior documentation"
        ),
        SessionToolUse(
            toolUseId: "multi-3",
            toolName: "Grep",
            summary: "Grep tool_result error handling branches"
        ),
    ]

    static let multiCompleted: [SessionToolUse] = [
        SessionToolUse(
            toolUseId: "multi-4",
            toolName: "Read",
            summary: "Read SessionMessagePayloadParser.swift"
        ),
        SessionToolUse(
            toolUseId: "multi-5",
            toolName: "Write",
            summary: "Write parser state documentation"
        ),
    ]

    enum ToolStatusProfile {
        case singleRunning
        case singleCompleted
        case singleFailed
        case multiMixed
        case multiCompleted
    }

    static let scenarios: [StandaloneToolCallsPreviewScenario] = [
        StandaloneToolCallsPreviewScenario(
            id: "single-running",
            title: "Single running (inline card)",
            tools: singleRunning,
            defaultExpanded: false,
            showToolStatusLabels: true,
            statusProfile: .singleRunning
        ),
        StandaloneToolCallsPreviewScenario(
            id: "single-completed",
            title: "Single completed (inline card)",
            tools: singleCompleted,
            defaultExpanded: false,
            showToolStatusLabels: false,
            statusProfile: .singleCompleted
        ),
        StandaloneToolCallsPreviewScenario(
            id: "single-failed",
            title: "Single failed multiline",
            tools: singleFailed,
            defaultExpanded: false,
            showToolStatusLabels: true,
            statusProfile: .singleFailed
        ),
        StandaloneToolCallsPreviewScenario(
            id: "multi-collapsed",
            title: "Multi collapsed",
            tools: multiCompleted,
            defaultExpanded: false,
            showToolStatusLabels: false,
            statusProfile: .multiCompleted
        ),
        StandaloneToolCallsPreviewScenario(
            id: "multi-expanded-mixed",
            title: "Multi expanded mixed status",
            tools: multiMixed,
            defaultExpanded: true,
            showToolStatusLabels: true,
            statusProfile: .multiMixed
        ),
    ]

    static func status(for tool: SessionToolUse, profile: ToolStatusProfile) -> ToolCallVisualStatus {
        switch profile {
        case .singleRunning:
            return .running

        case .singleCompleted:
            return .completed

        case .singleFailed:
            return .failed

        case .multiCompleted:
            return .completed

        case .multiMixed:
            if tool.toolName == "Write" {
                return .running
            }
            if tool.toolName == "Grep" {
                return .failed
            }
            return .completed
        }
    }
}

private struct StandaloneToolCallsPreviewScenario: Identifiable {
    let id: String
    let title: String
    let tools: [SessionToolUse]
    let defaultExpanded: Bool
    let showToolStatusLabels: Bool
    let statusProfile: StandaloneToolCallsPreviewData.ToolStatusProfile
}

#Preview("Standalone Tool Calls Variants") {
    VStack(alignment: .leading, spacing: AppTheme.spacingS) {
        ForEach(StandaloneToolCallsPreviewData.scenarios) { scenario in
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.title)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                StandaloneToolCallsView(
                    tools: scenario.tools,
                    defaultExpanded: scenario.defaultExpanded,
                    showToolStatusLabels: scenario.showToolStatusLabels,
                    statusForTool: { tool in
                        StandaloneToolCallsPreviewData.status(for: tool, profile: scenario.statusProfile)
                    }
                )
            }
        }
    }
    .frame(maxWidth: 560, alignment: .leading)
    .padding()
    .background(AppTheme.backgroundPrimary)
}
