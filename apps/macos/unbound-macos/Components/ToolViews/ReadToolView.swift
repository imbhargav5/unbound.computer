//
//  ReadToolView.swift
//  unbound-macos
//
//  Syntax-highlighted file content display for Read tool
//

import SwiftUI
import Logging

private let logger = Logger(label: "app.ui")

// MARK: - Read Tool View

/// File path header with syntax-highlighted content using HighlightedCodeText
struct ReadToolView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
    }

    /// Extract file extension for syntax highlighting
    private var fileLanguage: String? {
        guard let path = parser.filePath else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx": return "typescript"
        case "js", "jsx": return "javascript"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "json": return "json"
        case "sh", "bash", "zsh": return "bash"
        case "sql": return "sql"
        default: return nil
        }
    }

    /// Extract just the filename from the path
    private var filename: String? {
        guard let path = parser.filePath else { return nil }
        return (path as NSString).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ToolHeader(
                toolName: "Read",
                status: toolUse.status,
                subtitle: parser.filePath,
                icon: ToolIcon.icon(for: "Read"),
                isExpanded: isExpanded,
                hasContent: toolUse.output != nil,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded, let output = toolUse.output, !output.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // File header bar
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)

                        if let filename = filename {
                            Text(filename)
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                        }

                        if let lang = fileLanguage {
                            Text(lang)
                                .font(Typography.caption)
                                .foregroundStyle(colors.mutedForeground)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(colors.muted)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(colors.muted)

                    // Syntax highlighted content
                    ScrollView(.horizontal, showsIndicators: false) {
                        ScrollView(.vertical, showsIndicators: true) {
                            HighlightedCodeText(code: output, language: fileLanguage)
                                .padding(Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    }
                    .background(colors.card)
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
        ReadToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Read",
            input: "{\"file_path\": \"/src/main.swift\"}",
            output: """
            import Foundation

            func greet(name: String) -> String {
                // Return a greeting message
                let message = "Hello, \\(name)!"
                return message
            }

            let result = greet(name: "World")
            print(result)
            """,
            status: .completed
        ))

        ReadToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Read",
            input: "{\"file_path\": \"/package.json\"}",
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}

#endif
