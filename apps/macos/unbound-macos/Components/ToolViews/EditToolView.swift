//
//  EditToolView.swift
//  unbound-macos
//
//  Diff view display for Edit tool showing old/new string changes
//

import SwiftUI

// MARK: - Edit Tool View

/// File path with diff view showing the edit changes
struct EditToolView: View {
    @Environment(\.colorScheme) private var colorScheme

    let toolUse: ToolUse
    @State private var isExpanded = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var parser: ToolInputParser {
        ToolInputParser(toolUse.input)
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
                toolName: "Edit",
                status: toolUse.status,
                subtitle: parser.filePath,
                icon: ToolIcon.icon(for: "Edit"),
                isExpanded: isExpanded,
                hasContent: parser.oldString != nil || parser.newString != nil,
                onToggle: {
                    withAnimation(.easeInOut(duration: Duration.fast)) {
                        isExpanded.toggle()
                    }
                }
            )

            // Details (if expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // File header bar
                    HStack {
                        Image(systemName: "pencil.line")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.warning)

                        if let filename = filename {
                            Text(filename)
                                .font(Typography.caption)
                                .foregroundStyle(colors.foreground)
                        }

                        Text("Modified")
                            .font(Typography.caption)
                            .foregroundStyle(colors.warning)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(colors.warning.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xs))

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(colors.warning.opacity(0.05))

                    // Diff content
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Old string (deletion)
                        if let oldString = parser.oldString, !oldString.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: IconSize.sm))
                                        .foregroundStyle(colors.destructive)
                                    Text("Removed")
                                        .font(Typography.caption)
                                        .foregroundStyle(colors.destructive)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(oldString)
                                        .font(Typography.code)
                                        .foregroundStyle(colors.destructive)
                                        .textSelection(.enabled)
                                        .padding(Spacing.sm)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .background(colors.destructive.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            }
                        }

                        // New string (addition)
                        if let newString = parser.newString, !newString.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: IconSize.sm))
                                        .foregroundStyle(colors.success)
                                    Text("Added")
                                        .font(Typography.caption)
                                        .foregroundStyle(colors.success)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(newString)
                                        .font(Typography.code)
                                        .foregroundStyle(colors.success)
                                        .textSelection(.enabled)
                                        .padding(Spacing.sm)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .background(colors.success.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            }
                        }
                    }
                    .padding(Spacing.md)
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

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.md) {
        EditToolView(toolUse: ToolUse(
            toolUseId: "test-1",
            toolName: "Edit",
            input: """
            {"file_path": "/src/main.swift", "old_string": "let name = \\"World\\"", "new_string": "let name = \\"Universe\\""}
            """,
            status: .completed
        ))

        EditToolView(toolUse: ToolUse(
            toolUseId: "test-2",
            toolName: "Edit",
            input: """
            {"file_path": "/src/config.ts", "old_string": "const DEBUG = false;", "new_string": "const DEBUG = true;\\nconst VERBOSE = true;"}
            """,
            status: .completed
        ))
    }
    .frame(width: 500)
    .padding()
}
