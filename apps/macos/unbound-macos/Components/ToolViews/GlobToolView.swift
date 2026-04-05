//
//  GlobToolView.swift
//  unbound-macos
//
//  File list display for Glob tool results
//

import SwiftUI

// MARK: - Glob Tool View

/// File list display with icons for file types
struct GlobToolView: View {
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

    /// Parse output into file paths
    private var filePaths: [String] {
        outputParser.lines.filter { !$0.isEmpty }
    }

    /// Count of files found
    private var fileCount: Int {
        filePaths.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ToolHeader(
                toolName: "Glob",
                status: toolUse.status,
                subtitle: "\(parser.pattern ?? "pattern") → \(fileCount) files",
                icon: ToolIcon.icon(for: "Glob"),
                isExpanded: isExpanded,
                hasContent: !filePaths.isEmpty,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded && !filePaths.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ShadcnDivider()

                    // File list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(filePaths.prefix(100).enumerated()), id: \.offset) { _, path in
                                FileListItem(path: path)
                            }

                            if filePaths.count > 100 {
                                Text("... and \(filePaths.count - 100) more files")
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.mutedForeground)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.sm)
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                    .frame(maxHeight: 250)
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

// MARK: - File List Item

struct FileListItem: View {
    @Environment(\.colorScheme) private var colorScheme

    let path: String

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Extract file extension
    private var fileExtension: String {
        (path as NSString).pathExtension.lowercased()
    }

    /// Get appropriate icon for file type
    private var fileIcon: String {
        switch fileExtension {
        case "swift": return "swift"
        case "ts", "tsx", "js", "jsx": return "chevron.left.forwardslash.chevron.right"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml": return "curlybraces"
        case "md", "txt": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "css", "scss", "sass": return "paintbrush"
        case "html": return "globe"
        default: return "doc"
        }
    }

    /// Get icon color based on file type - using amber theme colors
    private var iconColor: Color {
        switch fileExtension {
        case "swift": return colors.accentAmber           // Amber for Swift
        case "ts", "tsx": return colors.info              // Blue for TypeScript
        case "js", "jsx": return colors.accentAmber.opacity(0.8) // Amber variant for JS
        case "py": return colors.success                  // Green for Python
        case "json": return colors.info.opacity(0.7)      // Blue variant for JSON
        case "md": return colors.mutedForeground          // Muted for markdown
        default: return colors.mutedForeground
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: fileIcon)
                .font(.system(size: IconSize.sm))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(path)
                .font(Typography.code)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Preview

#if DEBUG

#Preview {
    VStack(spacing: Spacing.md) {
        GlobToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Glob",
            input: "{\"pattern\": \"**/*.swift\"}",
            output: """
            src/main.swift
            src/models/User.swift
            src/services/AuthService.swift
            tests/AuthServiceTests.swift
            """,
            status: .completed
        ))

        GlobToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Glob",
            input: "{\"pattern\": \"*.ts\"}",
            status: .running
        ))
    }
    .frame(width: 500)
    .padding()
}

#endif
