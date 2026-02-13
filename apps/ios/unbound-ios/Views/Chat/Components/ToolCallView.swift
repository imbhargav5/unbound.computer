//
//  ToolCallView.swift
//  unbound-ios
//
//  Reusable tool-call component for session detail/chat surfaces.
//

import SwiftUI

enum ToolCallVisualStatus: String, CaseIterable, Identifiable {
    case running
    case completed
    case failed

    var id: Self { self }

    var label: String {
        switch self {
        case .running:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .running:
            return "progress.indicator"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .running:
            return AppTheme.accent
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

struct ToolCallView: View {
    let tool: SessionToolUse
    var status: ToolCallVisualStatus = .completed
    var showStatusLabel: Bool = false
    var maxSummaryLines: Int = 1

    var body: some View {
        HStack(spacing: AppTheme.spacingS) {
            Image(systemName: tool.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 20)

            Text(tool.summary)
                .font(Typography.footnote)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(maxSummaryLines)

            Spacer(minLength: 4)

            statusView
        }
        .padding(.horizontal, AppTheme.spacingS + 2)
        .padding(.vertical, AppTheme.spacingXS + 2)
        .background(AppTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .running:
            HStack(spacing: AppTheme.spacingXS) {
                ProgressView()
                    .controlSize(.small)
                if showStatusLabel {
                    Text(status.label)
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(status.color)
                }
            }
        case .completed, .failed:
            HStack(spacing: AppTheme.spacingXS) {
                Image(systemName: status.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(status.color)
                if showStatusLabel {
                    Text(status.label)
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(status.color)
                }
            }
        }
    }
}

private struct ToolCallPreviewScenario: Identifiable {
    let id: String
    let title: String
    let tool: SessionToolUse
    let status: ToolCallVisualStatus
    let showStatusLabel: Bool
    let maxSummaryLines: Int
}

private enum ToolCallPreviewData {
    static let statusMatrixTool = SessionToolUse(
        toolUseId: "status-matrix",
        toolName: "Read",
        summary: "Read apps/ios/unbound-ios/Services/SessionDetail/SessionMessagePayloadParser.swift"
    )

    static let contentScenarios: [ToolCallPreviewScenario] = [
        ToolCallPreviewScenario(
            id: "completed-read",
            title: "Completed compact",
            tool: SessionToolUse(
                toolUseId: "tool-1",
                toolName: "Read",
                summary: "Read docs/README.md"
            ),
            status: .completed,
            showStatusLabel: false,
            maxSummaryLines: 1
        ),
        ToolCallPreviewScenario(
            id: "running-bash",
            title: "Running with label",
            tool: SessionToolUse(
                toolUseId: "tool-2",
                toolName: "Bash",
                summary: "pnpm test --filter parser"
            ),
            status: .running,
            showStatusLabel: true,
            maxSummaryLines: 1
        ),
        ToolCallPreviewScenario(
            id: "failed-write",
            title: "Failed multiline",
            tool: SessionToolUse(
                toolUseId: "tool-3",
                toolName: "Write",
                summary: "Write app/session/parser-contract.md with edge-case matrix"
            ),
            status: .failed,
            showStatusLabel: true,
            maxSummaryLines: 2
        ),
        ToolCallPreviewScenario(
            id: "completed-long",
            title: "Completed long summary",
            tool: SessionToolUse(
                toolUseId: "tool-4",
                toolName: "WebFetch",
                summary: "Fetch docs and normalize wrapped raw_json payload to preserve visible user text while hiding protocol artifacts"
            ),
            status: .completed,
            showStatusLabel: true,
            maxSummaryLines: 3
        ),
        ToolCallPreviewScenario(
            id: "fallback-icon",
            title: "Unknown tool fallback icon",
            tool: SessionToolUse(
                toolUseId: "tool-5",
                toolName: "CustomTool",
                summary: "Custom parser adapter fallback behavior"
            ),
            status: .completed,
            showStatusLabel: false,
            maxSummaryLines: 1
        ),
    ]
}

#Preview("Tool Call Status Matrix") {
    VStack(alignment: .leading, spacing: AppTheme.spacingS) {
        ForEach(ToolCallVisualStatus.allCases) { status in
            ToolCallView(
                tool: ToolCallPreviewData.statusMatrixTool,
                status: status,
                showStatusLabel: true,
                maxSummaryLines: 2
            )
        }
    }
    .frame(maxWidth: 520, alignment: .leading)
    .padding()
    .background(AppTheme.backgroundPrimary)
}

#Preview("Tool Call Content Variants") {
    VStack(alignment: .leading, spacing: AppTheme.spacingS) {
        ForEach(ToolCallPreviewData.contentScenarios) { scenario in
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.title)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                ToolCallView(
                    tool: scenario.tool,
                    status: scenario.status,
                    showStatusLabel: scenario.showStatusLabel,
                    maxSummaryLines: scenario.maxSummaryLines
                )
            }
        }
    }
    .frame(maxWidth: 520, alignment: .leading)
    .padding()
    .background(AppTheme.backgroundPrimary)
}
