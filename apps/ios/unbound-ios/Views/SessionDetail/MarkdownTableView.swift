//
//  MarkdownTableView.swift
//  unbound-ios
//
//  Markdown table parser and renderer for iOS session chat.
//

import MobileClaudeCodeConversationTimeline
import SwiftUI

// MARK: - Table View

struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                        TableCell(
                            content: header,
                            alignment: table.alignments[safe: index] ?? .leading,
                            isHeader: true
                        )
                        if index < table.headers.count - 1 {
                            Divider()
                                .background(AppTheme.cardBorder)
                        }
                    }
                }
                .background(AppTheme.backgroundSecondary)

                Divider()
                    .background(AppTheme.cardBorder)

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            TableCell(
                                content: cell,
                                alignment: table.alignments[safe: colIndex] ?? .leading,
                                isHeader: false
                            )
                            if colIndex < row.count - 1 {
                                Divider()
                                    .background(AppTheme.cardBorder)
                            }
                        }
                    }
                    .background(rowIndex % 2 == 1 ? AppTheme.backgroundSecondary.opacity(0.4) : Color.clear)

                    if rowIndex < table.rows.count - 1 {
                        Divider()
                            .background(AppTheme.cardBorder.opacity(0.6))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .padding(.vertical, AppTheme.spacingXS)
    }
}

// MARK: - Table Cell

private struct TableCell: View {
    let content: String
    let alignment: TableCellAlignment
    let isHeader: Bool

    var body: some View {
        let baseFont = isHeader ? Typography.caption.weight(.semibold) : Typography.footnote
        InlineMarkdownText(content, baseFont: baseFont)
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(minWidth: 120, alignment: alignment.alignment)
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .textSelection(.enabled)
            .lineSpacing(2)
    }
}

private extension TableCellAlignment {
    var alignment: Alignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
