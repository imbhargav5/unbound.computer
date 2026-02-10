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
            ToolUseCardView(tool: tool)

        case .error(let message):
            ErrorBannerView(message: message)
        }
    }
}

// MARK: - Tool Use Card

private struct ToolUseCardView: View {
    let tool: SessionToolUse

    var body: some View {
        HStack(spacing: AppTheme.spacingS) {
            Image(systemName: tool.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 20)

            Text(tool.summary)
                .font(Typography.footnote)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, AppTheme.spacingS + 2)
        .padding(.vertical, AppTheme.spacingXS + 2)
        .background(AppTheme.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
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
