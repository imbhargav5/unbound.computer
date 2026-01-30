//
//  DiffViewer.swift
//  unbound-macos
//
//  Main diff viewer container with mode toggle
//  Inspired by @pierre/diffs library
//

import SwiftUI

// MARK: - Diff Viewer

/// Main diff viewer component that displays file diffs
struct DiffViewer: View {
    @Environment(\.colorScheme) private var colorScheme

    let diff: FileDiff
    @State private var viewMode: DiffViewMode = .unified
    @State private var isCollapsed: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DiffViewerHeader(
                diff: diff,
                viewMode: $viewMode,
                isCollapsed: $isCollapsed
            )

            if !isCollapsed {
                ShadcnDivider()

                // Content based on mode
                if diff.isBinary {
                    BinaryDiffView()
                } else if diff.hunks.isEmpty {
                    EmptyDiffView()
                } else {
                    ScrollView {
                        switch viewMode {
                        case .unified:
                            UnifiedDiffView(hunks: diff.hunks)
                        case .split:
                            SplitDiffView(hunks: diff.hunks)
                        }
                    }
                }
            }
        }
        .background(colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(colors.border, lineWidth: BorderWidth.default)
        )
    }
}

// MARK: - Diff Viewer Header

struct DiffViewerHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let diff: FileDiff
    @Binding var viewMode: DiffViewMode
    @Binding var isCollapsed: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Collapse toggle
            Button {
                withAnimation(.easeInOut(duration: Duration.fast)) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: IconSize.sm, weight: .semibold))
                    .foregroundStyle(colors.mutedForeground)
            }
            .buttonStyle(.plain)

            // File icon
            Image(systemName: fileIcon)
                .font(.system(size: IconSize.sm))
                .foregroundStyle(changeTypeColor)

            // File path
            Text(diff.filePath)
                .font(Typography.code)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            // Rename indicator
            if let oldPath = diff.oldPath {
                Text("←")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground)
                Text(oldPath)
                    .font(Typography.code)
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Stats
            HStack(spacing: Spacing.sm) {
                if diff.linesAdded > 0 {
                    Text("+\(diff.linesAdded)")
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.success)
                }
                if diff.linesRemoved > 0 {
                    Text("-\(diff.linesRemoved)")
                        .font(Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(colors.destructive)
                }
            }

            // View mode picker (only show when not collapsed and has content)
            if !isCollapsed && !diff.hunks.isEmpty && !diff.isBinary {
                Menu {
                    ForEach(DiffViewMode.allCases) { mode in
                        Button {
                            viewMode = mode
                        } label: {
                            Label(mode.rawValue, systemImage: mode.iconName)
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: viewMode.iconName)
                            .font(.system(size: IconSize.xs))
                        Image(systemName: "chevron.down")
                            .font(.system(size: IconSize.xs))
                    }
                    .foregroundStyle(colors.mutedForeground)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(colors.muted)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var fileIcon: String {
        switch diff.changeType {
        case .created: return "doc.badge.plus"
        case .modified: return "doc.badge.ellipsis"
        case .deleted: return "doc.badge.minus"
        case .renamed: return "arrow.right.doc.on.clipboard"
        }
    }

    private var changeTypeColor: Color {
        switch diff.changeType {
        case .created: return colors.success
        case .modified: return colors.warning
        case .deleted: return colors.destructive
        case .renamed: return colors.info
        }
    }
}

// MARK: - Binary Diff View

struct BinaryDiffView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "doc.zipper")
                .font(.system(size: IconSize.md))
            Text("Binary file changed")
                .font(Typography.body)
        }
        .foregroundStyle(colors.mutedForeground)
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Empty Diff View

struct EmptyDiffView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: IconSize.md))
            Text("No changes")
                .font(Typography.body)
        }
        .foregroundStyle(colors.mutedForeground)
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.lg) {
        DiffViewer(diff: FileDiff(
            filePath: "src/components/Button.swift",
            changeType: .modified,
            hunks: [
                DiffHunk(
                    oldStart: 10,
                    oldCount: 5,
                    newStart: 10,
                    newCount: 7,
                    context: "struct Button: View",
                    lines: [
                        DiffLine(type: .context, content: "    var label: String", oldLineNumber: 10, newLineNumber: 10),
                        DiffLine(type: .deletion, content: "    var style: ButtonStyle = .primary", oldLineNumber: 11, newLineNumber: nil),
                        DiffLine(type: .addition, content: "    var style: ButtonStyle", oldLineNumber: nil, newLineNumber: 11),
                        DiffLine(type: .addition, content: "    var isDisabled: Bool = false", oldLineNumber: nil, newLineNumber: 12),
                        DiffLine(type: .context, content: "", oldLineNumber: 12, newLineNumber: 13),
                    ]
                )
            ],
            linesAdded: 2,
            linesRemoved: 1
        ))

        DiffViewer(diff: FileDiff(
            filePath: "assets/image.png",
            changeType: .modified,
            isBinary: true
        ))
    }
    .padding()
    .frame(width: 600)
}
