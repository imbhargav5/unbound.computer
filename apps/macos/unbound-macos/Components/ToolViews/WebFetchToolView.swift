//
//  WebFetchToolView.swift
//  unbound-macos
//
//  Web content display for WebFetch tool results
//

import SwiftUI

// MARK: - Web Fetch Tool View

/// URL header with fetched content preview
struct WebFetchToolView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    /// Extract domain from URL for display
    private var domain: String? {
        guard let urlString = parser.url,
              let url = URL(string: urlString) else { return nil }
        return url.host
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ToolHeader(
                toolName: "WebFetch",
                status: toolUse.status,
                subtitle: domain ?? parser.url,
                icon: ToolIcon.icon(for: "WebFetch"),
                isExpanded: isExpanded,
                hasContent: toolUse.output != nil || parser.url != nil,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // URL bar
                    if let url = parser.url {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "link")
                                .font(.system(size: IconSize.sm))
                                .foregroundStyle(colors.info)

                            Text(url)
                                .font(Typography.code)
                                .foregroundStyle(colors.info)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            // Open in browser button
                            if let urlObj = URL(string: url) {
                                Button {
                                    NSWorkspace.shared.open(urlObj)
                                } label: {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: IconSize.sm))
                                        .foregroundStyle(colors.mutedForeground)
                                }
                                .buttonStyle(.plain)
                                .help("Open in browser")
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(colors.info.opacity(0.05))
                    }

                    // Prompt (if present)
                    if let prompt = parser.prompt {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: IconSize.sm))
                                .foregroundStyle(colors.mutedForeground)

                            Text(prompt)
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                    }

                    ShadcnDivider()

                    // Content
                    if let output = toolUse.output, !output.isEmpty {
                        ScrollView {
                            Text(output)
                                .font(Typography.body)
                                .foregroundStyle(colors.foreground)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Spacing.md)
                        }
                        .frame(maxHeight: 250)
                    } else if toolUse.status == .running {
                        HStack {
                            Spacer()
                            VStack(spacing: Spacing.sm) {
                                ProgressView()
                                Text("Fetching content...")
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
}

// MARK: - Preview

#if DEBUG

#Preview {
    VStack(spacing: Spacing.md) {
        WebFetchToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "WebFetch",
            input: "{\"url\": \"https://docs.swift.org/swift-book/\", \"prompt\": \"Extract the main topics\"}",
            output: """
            The Swift Programming Language documentation covers:
            - Welcome to Swift
            - A Swift Tour
            - Language Guide
            - Language Reference
            """,
            status: .completed
        ))

        WebFetchToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "WebFetch",
            input: "{\"url\": \"https://api.example.com/data\"}",
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}

#endif
