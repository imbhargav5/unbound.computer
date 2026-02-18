//
//  SessionContentBlockView.swift
//  unbound-ios
//
//  Dispatcher view that renders parsed session content blocks.
//

import SwiftUI

struct SessionContentBlockView: View {
    let block: SessionContentBlock

    var body: some View {
        switch block {
        case .text(let text):
            SessionMarkdownTextView(text: text)

        case .toolUse(let tool):
            StandaloneToolCallsView(tools: [tool], showToolStatusLabels: false)

        case .subAgentActivity(let activity):
            ParallelAgentsView(activities: [activity])

        case .error(let message):
            ErrorBannerView(message: message)
        }
    }
}

private enum SessionContentBlockPreviewData {
    static let tool = SessionToolUse(
        toolUseId: "tool-preview-1",
        toolName: "Read",
        summary: "Read SessionMessagePayloadParser.swift"
    )

    static let subAgent = SessionSubAgentActivity(
        parentToolUseId: "task-preview-1",
        subagentType: "Plan",
        description: "Map parser states to reusable components",
        tools: [
            SessionToolUse(
                toolUseId: "task-tool-1",
                parentToolUseId: "task-preview-1",
                toolName: "Read",
                summary: "Read SessionDetailMessageMapper.swift"
            ),
            SessionToolUse(
                toolUseId: "task-tool-2",
                parentToolUseId: "task-preview-1",
                toolName: "Write",
                summary: "Write block rendering notes"
            ),
        ]
    )
}

// MARK: - Error Banner

private struct ErrorBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: AppTheme.spacingXS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)

            Text(message)
                .font(Typography.footnote)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(3)
        }
        .padding(.horizontal, AppTheme.spacingS + 2)
        .padding(.vertical, AppTheme.spacingXS + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }
}

#Preview("Session Content Blocks") {
    VStack(alignment: .leading, spacing: AppTheme.spacingS) {
        SessionContentBlockView(block: .text("Assistant summary text with markdown support."))
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.vertical, AppTheme.spacingS + 2)
            .background(AppTheme.assistantBubble)
            .clipShape(MessageBubbleShape(isUser: false))

        SessionContentBlockView(block: .toolUse(SessionContentBlockPreviewData.tool))
        SessionContentBlockView(block: .subAgentActivity(SessionContentBlockPreviewData.subAgent))
        SessionContentBlockView(block: .error("Tool failed to parse wrapped raw_json payload"))
    }
    .padding()
    .background(AppTheme.backgroundPrimary)
}
