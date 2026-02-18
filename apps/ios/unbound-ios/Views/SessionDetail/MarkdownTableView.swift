//
//  MarkdownTableView.swift
//  unbound-ios
//
//  Markdown table parser and renderer for iOS session chat.
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

// MARK: - Parser

enum MarkdownTableParser {
    static func parseTable(_ lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2 else { return nil }

        var allRows: [[String]] = []
        for line in lines {
            let cells = parseCells(from: line)
            if !cells.isEmpty {
                allRows.append(cells)
            }
        }

        guard allRows.count >= 2 else { return nil }
        guard isSeparatorRow(allRows[1]) else { return nil }

        let headers = allRows[0]
        let separatorRow = allRows[1]
        let dataRows = Array(allRows.dropFirst(2))

        var alignments: [TableCellAlignment] = []
        for cell in separatorRow {
            alignments.append(parseAlignment(from: cell))
        }

        while alignments.count < headers.count {
            alignments.append(.leading)
        }

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

    static func isSeparatorRowLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let separatorPattern = #"^\|?[\s:-]+\|[\s|:-]*$"#
        guard let regex = try? NSRegularExpression(pattern: separatorPattern) else { return false }
        return regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
    }

    private static func parseCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)

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

    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("-") else { return false }
            for char in trimmed {
                if char != "-" && char != ":" && char != " " {
                    return false
                }
            }
        }
        return true
    }
}

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
            .frame(minWidth: 120, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
            .padding(.horizontal, AppTheme.spacingS)
            .padding(.vertical, AppTheme.spacingXS)
            .textSelection(.enabled)
            .lineSpacing(2)
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
