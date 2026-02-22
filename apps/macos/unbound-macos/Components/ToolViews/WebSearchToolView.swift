//
//  WebSearchToolView.swift
//  unbound-macos
//
//  Search results display for WebSearch tool with clickable links
//

import SwiftUI

// MARK: - Web Search Tool View

/// Search results display with titles, snippets, and clickable links
struct WebSearchToolView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ToolHeader(
                toolName: "WebSearch",
                status: toolUse.status,
                subtitle: parser.query,
                icon: ToolIcon.icon(for: "WebSearch"),
                isExpanded: isExpanded,
                hasContent: toolUse.output != nil,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Search query header
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.info)

                        if let query = parser.query {
                            Text("\"\(query)\"")
                                .font(Typography.body)
                                .foregroundStyle(colors.foreground)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(colors.info.opacity(0.05))

                    ShadcnDivider()

                    // Results content
                    if let output = toolUse.output, !output.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                // Parse and display search results
                                ForEach(parseSearchResults(output), id: \.id) { result in
                                    SearchResultCard(result: result)
                                }
                            }
                            .padding(Spacing.md)
                        }
                        .frame(maxHeight: 300)
                    } else if toolUse.status == .running {
                        HStack {
                            Spacer()
                            VStack(spacing: Spacing.sm) {
                                ProgressView()
                                Text("Searching...")
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.mutedForeground)
                            }
                            Spacer()
                        }
                        .padding(Spacing.lg)
                    }
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

    /// Parse search results from output (simple text format)
    private func parseSearchResults(_ output: String) -> [SearchResult] {
        // Just split by double newlines or return as single result
        let blocks = output.components(separatedBy: "\n\n")
        return blocks.enumerated().map { index, block in
            SearchResult(
                id: index,
                title: extractTitle(from: block),
                snippet: block,
                url: extractURL(from: block)
            )
        }
    }

    /// Try to extract a title from a block (first line or markdown link)
    private func extractTitle(from block: String) -> String? {
        let lines = block.components(separatedBy: .newlines)
        if let firstLine = lines.first, !firstLine.isEmpty {
            // Check for markdown link format [title](url)
            if let match = firstLine.firstMatch(of: /\[([^\]]+)\]/) {
                return String(match.output.1)
            }
            return firstLine
        }
        return nil
    }

    /// Try to extract a URL from a block
    private func extractURL(from block: String) -> URL? {
        // Look for URLs in the text
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(block.startIndex..., in: block)
        if let match = detector?.firstMatch(in: block, range: range) {
            return match.url
        }
        return nil
    }
}

// MARK: - Search Result Model

struct SearchResult: Identifiable {
    let id: Int
    let title: String?
    let snippet: String
    let url: URL?
}

// MARK: - Search Result Card

struct SearchResultCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let result: SearchResult

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Title
            if let title = result.title {
                Text(title)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(colors.info)
                    .lineLimit(2)
            }

            // Snippet
            Text(result.snippet)
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
                .lineLimit(3)

            // URL link
            if let url = result.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: IconSize.xs))

                        Text(url.host ?? url.absoluteString)
                            .font(Typography.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(colors.info)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(colors.muted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Preview

#if DEBUG

#Preview {
    VStack(spacing: Spacing.md) {
        WebSearchToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "WebSearch",
            input: "{\"query\": \"SwiftUI best practices 2024\"}",
            output: """
            [SwiftUI Best Practices](https://developer.apple.com/swiftui)
            Learn the latest patterns and practices for building SwiftUI apps with Apple's recommended guidelines.

            [WWDC 2024 SwiftUI Updates](https://developer.apple.com/wwdc24)
            Discover the new features and improvements in SwiftUI introduced at WWDC 2024.
            """,
            status: .completed
        ))

        WebSearchToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "WebSearch",
            input: "{\"query\": \"async await swift\"}",
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}

#endif
