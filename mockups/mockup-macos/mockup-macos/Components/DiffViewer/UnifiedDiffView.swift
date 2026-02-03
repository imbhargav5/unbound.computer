//
//  UnifiedDiffView.swift
//  unbound-macos
//
//  Unified (traditional) diff view with line-by-line changes
//  Inspired by @pierre/diffs library
//

import SwiftUI

// MARK: - Unified Diff View

/// Traditional unified diff view showing changes line by line
struct UnifiedDiffView: View {
    @Environment(\.colorScheme) private var colorScheme

    let hunks: [DiffHunk]
    let language: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hunks) { hunk in
                // Hunk header
                DiffHunkHeaderView(hunk: hunk)

                // Hunk lines
                ForEach(hunk.lines) { line in
                    DiffLineView(
                        line: line,
                        showBothLineNumbers: true,
                        language: language
                    )
                }

                // Spacing between hunks (except last)
                if hunk.id != hunks.last?.id {
                    HunkSeparator()
                }
            }
        }
    }
}

// MARK: - Diff Hunk Header View

struct DiffHunkHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme

    let hunk: DiffHunk

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Empty gutter space
            HStack(spacing: 0) {
                Text("")
                    .frame(width: DiffConstants.lineNumberWidth)
                Text("")
                    .frame(width: DiffConstants.lineNumberWidth)
            }
            .frame(width: DiffConstants.gutterWidth)
            .background(colors.muted.opacity(0.5))

            // Header content
            Text(hunk.headerString)
                .font(Typography.code)
                .foregroundStyle(colors.info)
                .padding(.horizontal, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DiffLineType.header.backgroundColor(colors: colors))
    }
}

// MARK: - Diff Line View

struct DiffLineView: View {
    @Environment(\.colorScheme) private var colorScheme

    let line: DiffLine
    var showBothLineNumbers: Bool = true
    let language: String?

    @State private var isHovered: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Line number gutter
            HStack(spacing: 0) {
                // Old line number
                Text(line.oldLineNumber.map { String($0) } ?? "")
                    .font(Typography.code)
                    .foregroundStyle(colors.mutedForeground)
                    .frame(width: DiffConstants.lineNumberWidth, alignment: .trailing)
                    .padding(.trailing, Spacing.xs)

                // New line number
                if showBothLineNumbers {
                    Text(line.newLineNumber.map { String($0) } ?? "")
                        .font(Typography.code)
                        .foregroundStyle(colors.mutedForeground)
                        .frame(width: DiffConstants.lineNumberWidth, alignment: .trailing)
                        .padding(.trailing, Spacing.xs)
                }
            }
            .frame(width: showBothLineNumbers ? DiffConstants.gutterWidth : DiffConstants.lineNumberWidth + Spacing.xs)
            .background(gutterBackground)

            // Change indicator
            Text(line.type.prefix)
                .font(Typography.code)
                .foregroundStyle(line.type.gutterColor(colors: colors))
                .frame(width: DiffConstants.indicatorWidth, alignment: .center)
                .background(line.type.backgroundColor(colors: colors))

            // Line content
            let content = line.content.isEmpty ? " " : line.content
            let highlighter = SyntaxHighlighter(language: language, colorScheme: colorScheme)
            Text(highlighter.highlight(content))
                .font(Typography.code)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.sm)
                .background(line.type.backgroundColor(colors: colors))
                .textSelection(.enabled)
        }
        .background(isHovered ? colors.muted.opacity(0.3) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var gutterBackground: Color {
        switch line.type {
        case .addition:
            return colors.success.opacity(0.1)
        case .deletion:
            return colors.destructive.opacity(0.1)
        default:
            return colors.muted.opacity(0.5)
        }
    }
}

// MARK: - Hunk Separator

struct HunkSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(colors.border)
                .frame(height: 1)
        }
        .padding(.vertical, Spacing.sm)
        .background(colors.muted.opacity(0.3))
    }
}

// MARK: - Constants

enum DiffConstants {
    static let lineNumberWidth: CGFloat = 40
    static let gutterWidth: CGFloat = 88  // Two line number columns + padding
    static let indicatorWidth: CGFloat = 20
}

// MARK: - Preview

#Preview {
    ScrollView {
        UnifiedDiffView(hunks: [
            DiffHunk(
                oldStart: 10,
                oldCount: 7,
                newStart: 10,
                newCount: 9,
                context: "struct Button: View",
                lines: [
                    DiffLine(type: .context, content: "    var label: String", oldLineNumber: 10, newLineNumber: 10),
                    DiffLine(type: .context, content: "    var action: () -> Void", oldLineNumber: 11, newLineNumber: 11),
                    DiffLine(type: .deletion, content: "    var style: ButtonStyle = .primary", oldLineNumber: 12, newLineNumber: nil),
                    DiffLine(type: .addition, content: "    var style: ButtonStyle", oldLineNumber: nil, newLineNumber: 12),
                    DiffLine(type: .addition, content: "    var isDisabled: Bool = false", oldLineNumber: nil, newLineNumber: 13),
                    DiffLine(type: .context, content: "", oldLineNumber: 13, newLineNumber: 14),
                    DiffLine(type: .context, content: "    var body: some View {", oldLineNumber: 14, newLineNumber: 15),
                ]
            ),
            DiffHunk(
                oldStart: 25,
                oldCount: 3,
                newStart: 27,
                newCount: 5,
                context: "extension Button",
                lines: [
                    DiffLine(type: .context, content: "    func makeBody() -> some View {", oldLineNumber: 25, newLineNumber: 27),
                    DiffLine(type: .addition, content: "        guard !isDisabled else {", oldLineNumber: nil, newLineNumber: 28),
                    DiffLine(type: .addition, content: "            return AnyView(EmptyView())", oldLineNumber: nil, newLineNumber: 29),
                    DiffLine(type: .addition, content: "        }", oldLineNumber: nil, newLineNumber: 30),
                    DiffLine(type: .context, content: "        return AnyView(content)", oldLineNumber: 26, newLineNumber: 31),
                ]
            )
        ], language: "swift")
    }
    .frame(width: 600, height: 400)
}
