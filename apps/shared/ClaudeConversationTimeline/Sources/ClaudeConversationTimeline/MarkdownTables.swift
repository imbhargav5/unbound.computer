//
//  MarkdownTables.swift
//  ClaudeConversationTimeline
//
//  Shared markdown table parsing + inline markdown tokenization.
//

import Foundation

// MARK: - Models

public struct MarkdownTable: Identifiable {
    public let id = UUID()
    public let headers: [String]
    public let rows: [[String]]
    public let alignments: [TableCellAlignment]

    public init(headers: [String], rows: [[String]], alignments: [TableCellAlignment]) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
    }
}

public enum TableCellAlignment {
    case leading
    case center
    case trailing
}

public enum TextContentSegment: Identifiable {
    case text(String)
    case table(MarkdownTable)

    public var id: String {
        switch self {
        case .text(let content):
            return "text-\(content.hashValue)"
        case .table(let table):
            return table.id.uuidString
        }
    }
}

// MARK: - Table Parser

public enum MarkdownTableParser {
    public static func parseContent(_ text: String) -> [TextContentSegment] {
        let lines = text.components(separatedBy: "\n")
        var segments: [TextContentSegment] = []
        var currentTextLines: [String] = []
        var tableLines: [String] = []
        var inTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isTableLine(trimmed) {
                if !inTable {
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
                    if let table = parseTable(tableLines) {
                        segments.append(.table(table))
                    } else {
                        currentTextLines.append(contentsOf: tableLines)
                    }
                    tableLines = []
                    inTable = false
                }
                currentTextLines.append(line)
            }
        }

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

    public static func parseTable(_ lines: [String]) -> MarkdownTable? {
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

    public static func isSeparatorRowLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let separatorPattern = #"^\|?[\s:-]+\|[\s|:-]*$"#
        guard let regex = try? NSRegularExpression(pattern: separatorPattern) else { return false }
        return regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
    }

    private static func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }

        let separatorPattern = #"^\|?[\s:-]+\|[\s|:-]*$"#
        if let regex = try? NSRegularExpression(pattern: separatorPattern),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }

        let cells = parseCells(from: trimmed)
        return !cells.isEmpty
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

// MARK: - Inline Markdown Tokenizer

public enum InlineMarkdownSpanStyle {
    case bold
    case italic
    case code
    case boldCode
}

public struct InlineMarkdownSpan: Identifiable {
    public let id = UUID()
    public let text: String
    public let style: InlineMarkdownSpanStyle?

    public init(text: String, style: InlineMarkdownSpanStyle?) {
        self.text = text
        self.style = style
    }
}

public enum InlineMarkdownTokenizer {
    public static func tokenize(_ text: String) -> [InlineMarkdownSpan] {
        var processedRanges: [(Range<String.Index>, InlineMarkdownSpanStyle, String)] = []

        let patterns: [(pattern: String, style: InlineMarkdownSpanStyle)] = [
            (#"\*\*`([^`]+)`\*\*"#, .boldCode),
            (#"`([^`]+)`"#, .code),
            (#"\*\*([^*]+)\*\*"#, .bold),
            (#"__([^_]+)__"#, .bold),
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, .italic),
            (#"(?<!_)_([^_]+)_(?!_)"#, .italic)
        ]

        for (pattern, style) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let captureRange = Range(match.range(at: 1), in: text) else { continue }

                let capturedText = String(text[captureRange])
                processedRanges.append((fullRange, style, capturedText))
            }
        }

        processedRanges.sort { $0.0.lowerBound < $1.0.lowerBound }

        var filteredRanges: [(Range<String.Index>, InlineMarkdownSpanStyle, String)] = []
        var lastEnd = text.startIndex
        for (range, style, capturedText) in processedRanges {
            if range.lowerBound >= lastEnd {
                filteredRanges.append((range, style, capturedText))
                lastEnd = range.upperBound
            }
        }

        var spans: [InlineMarkdownSpan] = []
        var currentIndex = text.startIndex

        for (range, style, capturedText) in filteredRanges {
            if currentIndex < range.lowerBound {
                let plainText = String(text[currentIndex..<range.lowerBound])
                spans.append(InlineMarkdownSpan(text: plainText, style: nil))
            }
            spans.append(InlineMarkdownSpan(text: capturedText, style: style))
            currentIndex = range.upperBound
        }

        if currentIndex < text.endIndex {
            let plainText = String(text[currentIndex...])
            spans.append(InlineMarkdownSpan(text: plainText, style: nil))
        }

        return spans
    }
}
