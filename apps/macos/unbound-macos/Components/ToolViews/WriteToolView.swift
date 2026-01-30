//
//  WriteToolView.swift
//  unbound-macos
//
//  Display for Write tool showing file path and written content
//

import SwiftUI

// MARK: - Write Tool View

/// Show file path and written content preview
struct WriteToolView: View {
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
                toolName: "Write",
                status: toolUse.status,
                subtitle: parser.filePath,
                icon: ToolIcon.icon(for: "Write"),
                isExpanded: isExpanded,
                hasContent: parser.content != nil,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded, let content = parser.content, !content.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // File header bar
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.success)

                        if let filename = filename {
                            Text(filename)
                                .font(Typography.caption)
                                .foregroundStyle(colors.foreground)
                        }

                        Text("Created")
                            .font(Typography.caption)
                            .foregroundStyle(colors.success)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(colors.success.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))

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
                    .background(colors.success.opacity(0.05))

                    // Syntax highlighted content
                    ScrollView(.horizontal, showsIndicators: false) {
                        ScrollView(.vertical, showsIndicators: true) {
                            HighlightedCodeText(code: content, language: fileLanguage)
                                .padding(Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 250)
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

#Preview {
    VStack(spacing: Spacing.md) {
        WriteToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Write",
            input: """
            {"file_path": "/src/config.json", "content": "{\\n  \\"name\\": \\"my-app\\",\\n  \\"version\\": \\"1.0.0\\",\\n  \\"main\\": \\"index.js\\"\\n}"}
            """,
            status: .completed
        ))

        WriteToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Write",
            input: "{\"file_path\": \"/src/new-file.ts\"}",
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}
