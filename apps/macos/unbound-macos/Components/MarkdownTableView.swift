//
//  MarkdownTableView.swift
//  unbound-macos
//
//  Markdown table parser and renderer
//

import SwiftUI

// MARK: - Models

struct MarkdownTable: Identifiable {
    let id = UUID()
    let headers: [String]
    let rows: [[String]]
    let alignments: [TableCellAlignment]
}

enum TableCellAlignment {
    case leading
    case center
    case trailing

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

/// Represents segments of text content that may include tables
enum TextContentSegment: Identifiable {
    case text(String)
    case table(MarkdownTable)

    var id: String {
        switch self {
        case .text(let content):
            return "text-\(content.hashValue)"
        case .table(let table):
            return table.id.uuidString
        }
    }
}

// MARK: - Parser

enum MarkdownTableParser {
    /// Parse text content and extract tables, returning segments
    static func parseContent(_ text: String) -> [TextContentSegment] {
        let lines = text.components(separatedBy: "\n")
        var segments: [TextContentSegment] = []
        var currentTextLines: [String] = []
        var tableLines: [String] = []
        var inTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isTableLine(trimmed) {
                if !inTable {
                    // Starting a new table, flush text
                    if !currentTextLines.isEmpty {
                        let text = currentTextLines.joined(separator: "\n")
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            segments.append(.text(text))
                        }
                        currentTextLines = []
                    }
                    inTable = true
                }
                tableLines.append(trimmed)
            } else {
                if inTable {
                    // End of table, parse it
                    if let table = parseTable(tableLines) {
                        segments.append(.table(table))
                    } else {
                        // Failed to parse, add as text
                        currentTextLines.append(contentsOf: tableLines)
                    }
                    tableLines = []
                    inTable = false
                }
                currentTextLines.append(line)
            }
        }

        // Handle remaining content
        if inTable && !tableLines.isEmpty {
            if let table = parseTable(tableLines) {
                segments.append(.table(table))
            } else {
                currentTextLines.append(contentsOf: tableLines)
            }
        }

        if !currentTextLines.isEmpty {
            let text = currentTextLines.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(text))
            }
        }

        return segments
    }

    /// Check if a line looks like a table row
    private static func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Must start and end with | or contain at least one |
        // And have content between pipes
        guard trimmed.contains("|") else { return false }

        // Check for separator row pattern (e.g., |---|---|)
        let separatorPattern = #"^\|?[\s:-]+\|[\s|:-]*$"#
        if let regex = try? NSRegularExpression(pattern: separatorPattern),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }

        // Check for data row pattern (has content between pipes)
        let cells = parseCells(from: trimmed)
        return cells.count >= 1
    }

    /// Parse cells from a table row
    private static func parseCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)

        // Remove leading/trailing pipes
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        return trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Parse alignment from separator row cell
    private static func parseAlignment(from cell: String) -> TableCellAlignment {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        let hasLeadingColon = trimmed.hasPrefix(":")
        let hasTrailingColon = trimmed.hasSuffix(":")

        if hasLeadingColon && hasTrailingColon {
            return .center
        } else if hasTrailingColon {
            return .trailing
        } else {
            return .leading
        }
    }

    /// Check if a row is a separator row
    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            // Must contain at least one dash and only dashes/colons/spaces
            guard trimmed.contains("-") else { return false }
            for char in trimmed {
                if char != "-" && char != ":" && char != " " {
                    return false
                }
            }
        }
        return true
    }

    /// Parse a complete table from lines
    private static func parseTable(_ lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2 else { return nil }

        // Parse all rows
        var allRows: [[String]] = []
        for line in lines {
            let cells = parseCells(from: line)
            if !cells.isEmpty {
                allRows.append(cells)
            }
        }

        guard allRows.count >= 2 else { return nil }

        // Find separator row (should be second row)
        guard allRows.count >= 2 && isSeparatorRow(allRows[1]) else { return nil }

        let headers = allRows[0]
        let separatorRow = allRows[1]
        let dataRows = Array(allRows.dropFirst(2))

        // Parse alignments from separator row
        var alignments: [TableCellAlignment] = []
        for cell in separatorRow {
            alignments.append(parseAlignment(from: cell))
        }

        // Ensure alignment count matches header count
        while alignments.count < headers.count {
            alignments.append(.leading)
        }

        // Normalize data rows to have same column count as headers
        let normalizedRows = dataRows.map { row -> [String] in
            var normalized = row
            while normalized.count < headers.count {
                normalized.append("")
            }
            return Array(normalized.prefix(headers.count))
        }

        return MarkdownTable(
            headers: headers,
            rows: normalizedRows,
            alignments: Array(alignments.prefix(headers.count))
        )
    }
}

// MARK: - Inline Markdown Parser

enum InlineMarkdownParser {
    /// Parse inline markdown (bold, italic, code) and return AttributedString
    static func parse(_ text: String, baseFont: Font, colors: ThemeColors) -> AttributedString {
        var result = AttributedString()

        let patterns: [(pattern: String, transform: (String, Font, ThemeColors) -> AttributedString)] = [
            // Code (backticks) - must come first
            (#"`([^`]+)`"#, { match, font, colors in
                var attr = AttributedString(match)
                attr.font = Typography.code
                attr.backgroundColor = colors.muted
                attr.foregroundColor = colors.foreground
                return attr
            }),
            // Bold (double asterisks or underscores)
            (#"\*\*([^*]+)\*\*"#, { match, font, colors in
                var attr = AttributedString(match)
                attr.font = font.weight(.semibold)
                return attr
            }),
            (#"__([^_]+)__"#, { match, font, colors in
                var attr = AttributedString(match)
                attr.font = font.weight(.semibold)
                return attr
            }),
            // Italic (single asterisk or underscore)
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, { match, font, colors in
                var attr = AttributedString(match)
                attr.font = font.italic()
                return attr
            }),
            (#"(?<!_)_([^_]+)_(?!_)"#, { match, font, colors in
                var attr = AttributedString(match)
                attr.font = font.italic()
                return attr
            })
        ]

        // Simple approach: process text segment by segment
        var remaining = text
        var processedRanges: [(Range<String.Index>, AttributedString)] = []

        // Find all matches for all patterns
        for (pattern, transform) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let captureRange = Range(match.range(at: 1), in: text) else { continue }

                let capturedText = String(text[captureRange])
                let formatted = transform(capturedText, baseFont, colors)

                processedRanges.append((fullRange, formatted))
            }
        }

        // Sort ranges by start position
        processedRanges.sort { $0.0.lowerBound < $1.0.lowerBound }

        // Remove overlapping ranges (keep first match)
        var filteredRanges: [(Range<String.Index>, AttributedString)] = []
        var lastEnd: String.Index = text.startIndex
        for (range, attr) in processedRanges {
            if range.lowerBound >= lastEnd {
                filteredRanges.append((range, attr))
                lastEnd = range.upperBound
            }
        }

        // Build result
        var currentIndex = text.startIndex
        for (range, formatted) in filteredRanges {
            // Add plain text before this match
            if currentIndex < range.lowerBound {
                let plainText = String(text[currentIndex..<range.lowerBound])
                result.append(AttributedString(plainText))
            }
            // Add formatted text
            result.append(formatted)
            currentIndex = range.upperBound
        }

        // Add remaining plain text
        if currentIndex < text.endIndex {
            let plainText = String(text[currentIndex...])
            result.append(AttributedString(plainText))
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
                            Divider()
                                .frame(height: 32)
                                .background(colors.border)
                        }
                    }
                }
                .background(colors.muted)

                Divider()
                    .background(colors.border)

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
                                Divider()
                                    .frame(height: 28)
                                    .background(colors.border)
                            }
                        }
                    }
                    .background(rowIndex % 2 == 1 ? colors.muted.opacity(0.3) : Color.clear)

                    if rowIndex < table.rows.count - 1 {
                        Divider()
                            .background(colors.border.opacity(0.5))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(colors.border, lineWidth: BorderWidth.default)
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
        Text(InlineMarkdownParser.parse(content, baseFont: Typography.bodySmall, colors: colors))
            .font(isHeader ? Typography.label : Typography.bodySmall)
            .foregroundStyle(colors.foreground)
            .multilineTextAlignment(alignment.textAlignment)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
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
