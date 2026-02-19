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

// MARK: - Table Tokens + Layout Helpers

enum MarkdownTableStyleTokens {
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
    static let rowVerticalPadding: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 14
    static let sectionHeadingGap: CGFloat = 8
    static let sectionToSectionGap: CGFloat = 24
    static let minimumColumnWidth: CGFloat = 180

    static func headerBackground(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "1A1A1A") : colors.secondary
    }

    static func tableBorderAndDividers(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "2A2A2A") : colors.border
    }

    static func headerText(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "8A8A8A") : colors.textMuted
    }

    static func fileColumnText(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "A3A3A3") : colors.gray525
    }

    static func bodyText(colors: ThemeColors, colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "8A8A8A") : colors.textMuted
    }

}

struct MarkdownTableNormalizedContent {
    let columnCount: Int
    let headers: [String]
    let rows: [[String]]
    let alignments: [TableCellAlignment]
}

enum MarkdownTableLayoutHelper {
    static let fileLikeHeaderKeywords: Set<String> = [
        "file",
        "path",
        "location",
        "filepath",
        "file path",
        "source",
        "target"
    ]

    static func normalizedHeader(_ header: String) -> String {
        header
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
            .joined(separator: " ")
    }

    static func fileLikeColumnIndices(headers: [String]) -> Set<Int> {
        Set(
            headers.enumerated().compactMap { index, header in
                let normalized = normalizedHeader(header)
                return fileLikeHeaderKeywords.contains(normalized) ? index : nil
            }
        )
    }

    static func normalize(table: MarkdownTable) -> MarkdownTableNormalizedContent {
        normalize(headers: table.headers, rows: table.rows, alignments: table.alignments)
    }

    static func normalize(
        headers: [String],
        rows: [[String]],
        alignments: [TableCellAlignment]
    ) -> MarkdownTableNormalizedContent {
        let maximumRowCount = rows.map(\.count).max() ?? 0
        let columnCount = max(headers.count, maximumRowCount)

        var normalizedHeaders = headers
        while normalizedHeaders.count < columnCount {
            normalizedHeaders.append("")
        }
        normalizedHeaders = Array(normalizedHeaders.prefix(columnCount))

        let normalizedRows = rows.map { row in
            var normalized = row
            while normalized.count < columnCount {
                normalized.append("")
            }
            return Array(normalized.prefix(columnCount))
        }

        var normalizedAlignments = alignments
        while normalizedAlignments.count < columnCount {
            normalizedAlignments.append(.leading)
        }
        normalizedAlignments = Array(normalizedAlignments.prefix(columnCount))

        return MarkdownTableNormalizedContent(
            columnCount: columnCount,
            headers: normalizedHeaders,
            rows: normalizedRows,
            alignments: normalizedAlignments
        )
    }
}

// MARK: - Table View

struct MarkdownTableView: View {
    @Environment(\.colorScheme) private var colorScheme

    let table: MarkdownTable

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var normalizedContent: MarkdownTableNormalizedContent {
        MarkdownTableLayoutHelper.normalize(table: table)
    }

    private var fileLikeColumns: Set<Int> {
        MarkdownTableLayoutHelper.fileLikeColumnIndices(headers: normalizedContent.headers)
    }

    private var minimumTableWidth: CGFloat {
        CGFloat(normalizedContent.columnCount) * MarkdownTableStyleTokens.minimumColumnWidth
    }

    private var borderColor: Color {
        MarkdownTableStyleTokens.tableBorderAndDividers(colors: colors, colorScheme: colorScheme)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tableContent()
            ScrollView(.horizontal, showsIndicators: false) {
                tableContent()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func tableContent() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(normalizedContent.headers.enumerated()), id: \.offset) { index, header in
                    TableCell(
                        content: header,
                        alignment: normalizedContent.alignments[safe: index] ?? .leading,
                        isHeader: true,
                        isFileLike: fileLikeColumns.contains(index),
                        colorScheme: colorScheme,
                        colors: colors
                    )
                }
            }
            .padding(.horizontal, MarkdownTableStyleTokens.rowHorizontalPadding)
            .padding(.vertical, MarkdownTableStyleTokens.rowVerticalPadding)
            .background(
                MarkdownTableStyleTokens.headerBackground(colors: colors, colorScheme: colorScheme)
            )

            ForEach(Array(normalizedContent.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                        TableCell(
                            content: cell,
                            alignment: normalizedContent.alignments[safe: colIndex] ?? .leading,
                            isHeader: false,
                            isFileLike: fileLikeColumns.contains(colIndex),
                            colorScheme: colorScheme,
                            colors: colors
                        )
                    }
                }
                .padding(.horizontal, MarkdownTableStyleTokens.rowHorizontalPadding)
                .padding(.vertical, MarkdownTableStyleTokens.rowVerticalPadding)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(borderColor)
                        .frame(height: MarkdownTableStyleTokens.borderWidth)
                }
            }
        }
        .frame(minWidth: minimumTableWidth, maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: MarkdownTableStyleTokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MarkdownTableStyleTokens.cornerRadius)
                .stroke(borderColor, lineWidth: MarkdownTableStyleTokens.borderWidth)
        )
    }
}

// MARK: - Table Cell

private struct TableCell: View {
    let content: String
    let alignment: TableCellAlignment
    let isHeader: Bool
    let isFileLike: Bool
    let colorScheme: ColorScheme
    let colors: ThemeColors

    @MainActor
    private var baseFont: Font {
        if isHeader {
            return GeistFont.sans(size: 12, weight: .semibold)
        }

        if isFileLike {
            return GeistFont.mono(size: 11, weight: .regular)
        }

        return GeistFont.sans(size: 12, weight: .regular)
    }

    private var foregroundColor: Color {
        if isHeader {
            return MarkdownTableStyleTokens.headerText(colors: colors, colorScheme: colorScheme)
        }

        if isFileLike {
            return MarkdownTableStyleTokens.fileColumnText(colors: colors, colorScheme: colorScheme)
        }

        return MarkdownTableStyleTokens.bodyText(colors: colors, colorScheme: colorScheme)
    }

    var body: some View {
        Text(InlineMarkdownParser.parse(content, baseFont: baseFont, colors: colors))
            .font(baseFont)
            .foregroundStyle(foregroundColor)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .top))
            .textSelection(.enabled)
            .lineSpacing(Spacing.xxs)
            .fixedSize(horizontal: false, vertical: true)
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
