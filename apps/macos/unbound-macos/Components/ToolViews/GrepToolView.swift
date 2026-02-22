//
//  GrepToolView.swift
//  unbound-macos
//
//  Search results display for Grep tool with file paths and highlighted matches
//

import SwiftUI

// MARK: - Grep Tool View

/// Search results display with file paths, line numbers, and highlighted matches
struct GrepToolView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    private var outputParser: ToolOutputParser {
        ToolOutputParser(toolUse.output)
    }

    /// Parse output into search results (file:line format or just file list)
    private var searchResults: [GrepResult] {
        outputParser.lines.compactMap { line in
            GrepResult(from: line, pattern: parser.pattern)
        }
    }

    /// Count of matches
    private var matchCount: Int {
        searchResults.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ToolHeader(
                toolName: "Grep",
                status: toolUse.status,
                subtitle: "\"\(parser.pattern ?? "pattern")\" → \(matchCount) matches",
                icon: ToolIcon.icon(for: "Grep"),
                isExpanded: isExpanded,
                hasContent: !searchResults.isEmpty,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded && !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ShadcnDivider()

                    // Search results
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(searchResults.prefix(50).enumerated()), id: \.offset) { _, result in
                                GrepResultRow(result: result, searchPattern: parser.pattern)
                            }

                            if searchResults.count > 50 {
                                Text("... and \(searchResults.count - 50) more matches")
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.mutedForeground)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.sm)
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }
}

// MARK: - Grep Result Model

struct GrepResult: Identifiable {
    let id = UUID()
    let filePath: String
    let lineNumber: Int?
    let content: String?

    init?(from line: String, pattern: String?) {
        // Try to parse "file:line:content" format
        let components = line.components(separatedBy: ":")
        if components.count >= 2 {
            self.filePath = components[0]
            self.lineNumber = Int(components[1])
            self.content = components.count > 2 ? components[2...].joined(separator: ":") : nil
        } else {
            // Just a file path
            self.filePath = line
            self.lineNumber = nil
            self.content = nil
        }
    }
}

// MARK: - Grep Result Row

struct GrepResultRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let result: GrepResult
    let searchPattern: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // File path and line number
            HStack(spacing: Spacing.xs) {
                Image(systemName: "doc.text")
                    .font(.system(size: IconSize.xs))
                    .foregroundStyle(colors.mutedForeground)

                Text(result.filePath)
                    .font(Typography.caption)
                    .foregroundStyle(colors.info)

                if let lineNum = result.lineNumber {
                    Text(":\(lineNum)")
                        .font(Typography.caption)
                        .foregroundStyle(colors.mutedForeground)
                }
            }

            // Content with highlighted match
            if let content = result.content {
                Text(highlightedContent(content))
                    .font(Typography.code)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    /// Highlight the search pattern in the content
    private func highlightedContent(_ content: String) -> AttributedString {
        var result = AttributedString(content)
        result.foregroundColor = colors.mutedForeground

        guard let pattern = searchPattern, !pattern.isEmpty else {
            return result
        }

        // Simple case-insensitive highlighting
        let lowercased = content.lowercased()
        let patternLower = pattern.lowercased()
        var searchStart = lowercased.startIndex

        while let range = lowercased.range(of: patternLower, range: searchStart..<lowercased.endIndex) {
            let attrRange = AttributedString.Index(range.lowerBound, within: result)!..<AttributedString.Index(range.upperBound, within: result)!
            result[attrRange].foregroundColor = colors.warning
            result[attrRange].backgroundColor = colors.warning.opacity(0.2)
            searchStart = range.upperBound
        }

        return result
    }
}

// MARK: - Preview

#if DEBUG

#Preview {
    VStack(spacing: Spacing.md) {
        GrepToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Grep",
            input: "{\"pattern\": \"TODO\"}",
            output: """
            src/main.swift:10:// TODO: Add error handling
            src/services/Auth.swift:25:// TODO: Implement refresh token
            tests/AuthTests.swift:5:// TODO: Add more test cases
            """,
            status: .completed
        ))

        GrepToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Grep",
            input: "{\"pattern\": \"error\"}",
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}

#endif
