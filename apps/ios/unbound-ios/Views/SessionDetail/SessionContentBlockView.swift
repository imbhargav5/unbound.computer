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
            ToolCallView(tool: tool)

        case .subAgentActivity(let activity):
            SubAgentView(activity: activity)

        case .error(let message):
            ErrorBannerView(message: message)
        }
    }
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
