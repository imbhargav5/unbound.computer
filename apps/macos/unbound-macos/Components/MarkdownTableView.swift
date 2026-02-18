//
//  MarkdownTableView.swift
//  unbound-macos
//
//  Markdown table parser and renderer
//

import ClaudeConversationTimeline
import SwiftUI

// MARK: - Inline Markdown Parser

enum InlineMarkdownParser {
    /// Parse inline markdown (bold, italic, code) and return AttributedString
    static func parse(_ text: String, baseFont: Font, colors: ThemeColors) -> AttributedString {
        var result = AttributedString()
        for span in InlineMarkdownTokenizer.tokenize(text) {
            var attr = AttributedString(span.text)
            switch span.style {
            case .bold:
                attr.font = baseFont.weight(.semibold)
            case .italic:
                attr.font = baseFont.italic()
            case .code:
                attr.font = Typography.code
                attr.backgroundColor = colors.muted
                attr.foregroundColor = colors.foreground
            case .boldCode:
                attr.font = Typography.code.weight(.semibold)
                attr.backgroundColor = colors.muted
                attr.foregroundColor = colors.foreground
            case .none:
                break
            }
            result.append(attr)
        }

        return result
    }
}

// MARK: - Table View

struct MarkdownTableView: View {
    @Environment(\.colorScheme) private var colorScheme

    let table: MarkdownTable

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                        TableCell(
                            content: header,
                            alignment: table.alignments[safe: index] ?? .leading,
                            isHeader: true,
                            colors: colors
                        )
                        if index < table.headers.count - 1 {
                            Rectangle()
                                .fill(colors.border.opacity(0.7))
                                .frame(width: BorderWidth.hairline, height: 28)
                        }
                    }
                }
                .background(colors.surface1)

                Rectangle()
                    .fill(colors.border.opacity(0.7))
                    .frame(height: BorderWidth.hairline)

                // Data rows
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            TableCell(
                                content: cell,
                                alignment: table.alignments[safe: colIndex] ?? .leading,
                                isHeader: false,
                                colors: colors
                            )
                            if colIndex < row.count - 1 {
                                Rectangle()
                                    .fill(colors.border.opacity(0.5))
                                    .frame(width: BorderWidth.hairline, height: 26)
                            }
                        }
                    }
                    .background(rowIndex % 2 == 1 ? colors.surface1.opacity(0.35) : Color.clear)

                    if rowIndex < table.rows.count - 1 {
                        Rectangle()
                            .fill(colors.border.opacity(0.5))
                            .frame(height: BorderWidth.hairline)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(colors.border.opacity(0.7), lineWidth: BorderWidth.hairline)
            )
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Table Cell

private struct TableCell: View {
    let content: String
    let alignment: TableCellAlignment
    let isHeader: Bool
    let colors: ThemeColors

    var body: some View {
        let baseFont = isHeader ? Typography.label : Typography.bodySmall
        Text(InlineMarkdownParser.parse(content, baseFont: baseFont, colors: colors))
            .font(baseFont)
            .foregroundStyle(colors.foreground)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .textSelection(.enabled)
            .lineSpacing(Spacing.xxs)
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension TableCellAlignment {
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
