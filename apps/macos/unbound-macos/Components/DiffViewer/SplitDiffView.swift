//
//  SplitDiffView.swift
//  unbound-macos
//
//  Side-by-side diff view comparing old and new versions
//  Inspired by @pierre/diffs library
//

import SwiftUI

// MARK: - Split Diff View

/// Side-by-side diff view showing old and new file versions
struct SplitDiffView: View {
    @Environment(\.colorScheme) private var colorScheme

    let hunks: [DiffHunk]
    let language: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column headers
            SplitDiffHeader()

            ShadcnDivider()

            // Hunks
            ForEach(hunks) { hunk in
                // Hunk header (spans both columns)
                SplitHunkHeader(hunk: hunk)

                // Split lines
                ForEach(Array(buildSplitLines(from: hunk.lines).enumerated()), id: \.offset) { _, pair in
                    SplitDiffLineRow(
                        leftLine: pair.left,
                        rightLine: pair.right,
                        language: language
                    )
                }

                // Spacing between hunks
                if hunk.id != hunks.last?.id {
                    HunkSeparator()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Build paired lines for split view
    /// Groups deletions with their corresponding additions
    private func buildSplitLines(from lines: [DiffLine]) -> [(left: DiffLine?, right: DiffLine?)] {
        var result: [(left: DiffLine?, right: DiffLine?)] = []
        var pendingDeletions: [DiffLine] = []
        var pendingAdditions: [DiffLine] = []

        for line in lines {
            switch line.type {
            case .context:
                // Flush pending changes
                result.append(contentsOf: flushPending(&pendingDeletions, &pendingAdditions))
                // Context lines appear on both sides
                result.append((left: line, right: line))

            case .deletion:
                pendingDeletions.append(line)

            case .addition:
                pendingAdditions.append(line)

            case .header:
                // Skip headers in split view (handled separately)
                break
            }
        }

        // Flush remaining
        result.append(contentsOf: flushPending(&pendingDeletions, &pendingAdditions))

        return result
    }

    /// Flush pending deletions and additions, pairing them up
    private func flushPending(
        _ deletions: inout [DiffLine],
        _ additions: inout [DiffLine]
    ) -> [(left: DiffLine?, right: DiffLine?)] {
        var result: [(left: DiffLine?, right: DiffLine?)] = []

        // Pair up deletions with additions
        let maxCount = max(deletions.count, additions.count)
        for i in 0..<maxCount {
            let left = i < deletions.count ? deletions[i] : nil
            let right = i < additions.count ? additions[i] : nil
            result.append((left: left, right: right))
        }

        deletions.removeAll()
        additions.removeAll()

        return result
    }
}

// MARK: - Split Diff Header

struct SplitDiffHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left header (old)
            HStack {
                Image(systemName: "minus.circle")
                    .font(.system(size: IconSize.xs))
                Text("Original")
                    .font(Typography.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            .foregroundStyle(colors.destructive)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(colors.destructive.opacity(0.05))

            // Divider
            Rectangle()
                .fill(colors.border)
                .frame(width: 1)

            // Right header (new)
            HStack {
                Image(systemName: "plus.circle")
                    .font(.system(size: IconSize.xs))
                Text("Modified")
                    .font(Typography.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            .foregroundStyle(colors.success)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(colors.success.opacity(0.05))
        }
    }
}

// MARK: - Split Hunk Header

struct SplitHunkHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let hunk: DiffHunk

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side info
            Text("@@ -\(hunk.oldStart),\(hunk.oldCount)")
                .font(Typography.code)
                .foregroundStyle(colors.info)
                .padding(.horizontal, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Divider
            Rectangle()
                .fill(colors.border)
                .frame(width: 1)

            // Right side info
            HStack {
                Text("+\(hunk.newStart),\(hunk.newCount) @@")
                    .font(Typography.code)
                    .foregroundStyle(colors.info)

                if let context = hunk.context {
                    Text(context)
                        .font(Typography.code)
                        .foregroundStyle(colors.mutedForeground)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.xs)
        .background(colors.info.opacity(0.1))
    }
}

// MARK: - Split Diff Line Row

struct SplitDiffLineRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let leftLine: DiffLine?
    let rightLine: DiffLine?
    let language: String?

    @State private var isHovered: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left side (old/deleted)
            SplitDiffLineCell(line: leftLine, side: .left, language: language)
                .frame(maxWidth: .infinity)

            // Divider
            Rectangle()
                .fill(colors.border)
                .frame(width: 1)

            // Right side (new/added)
            SplitDiffLineCell(line: rightLine, side: .right, language: language)
                .frame(maxWidth: .infinity)
        }
        .background(isHovered ? colors.muted.opacity(0.2) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Split Diff Line Cell

struct SplitDiffLineCell: View {
    @Environment(\.colorScheme) private var colorScheme

    let line: DiffLine?
    let side: DiffSide
    let language: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    enum DiffSide {
        case left
        case right
    }

    var body: some View {
        HStack(spacing: 0) {
            if let line = line {
                // Line number
                Text(lineNumber)
                    .font(Typography.code)
                    .foregroundStyle(colors.mutedForeground)
                    .frame(width: SplitDiffConstants.lineNumberWidth, alignment: .trailing)
                    .padding(.trailing, Spacing.xs)
                    .background(gutterBackground)

                // Content
                let content = line.content.isEmpty ? " " : line.content
                let highlighter = SyntaxHighlighter(language: language, colorScheme: colorScheme)
                Text(highlighter.highlight(content))
                    .font(Typography.code)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Spacing.sm)
                    .background(contentBackground)
                    .textSelection(.enabled)
            } else {
                // Empty cell
                Color.clear
                    .frame(maxWidth: .infinity)
                    .background(colors.muted.opacity(0.2))
            }
        }
    }

    private var lineNumber: String {
        guard let line = line else { return "" }
        switch side {
        case .left:
            return line.oldLineNumber.map { String($0) } ?? ""
        case .right:
            return line.newLineNumber.map { String($0) } ?? ""
        }
    }

    private var gutterBackground: Color {
        guard let line = line else { return colors.muted.opacity(0.2) }
        switch line.type {
        case .addition:
            return colors.success.opacity(0.1)
        case .deletion:
            return colors.destructive.opacity(0.1)
        default:
            return colors.muted.opacity(0.5)
        }
    }

    private var contentBackground: Color {
        guard let line = line else { return colors.muted.opacity(0.2) }
        return line.type.backgroundColor(colors: colors)
    }
}

// MARK: - Constants

enum SplitDiffConstants {
    static let lineNumberWidth: CGFloat = 40
}

// MARK: - Preview

#Preview {
    ScrollView {
        SplitDiffView(hunks: [
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
        ], language: "swift")
    }
    .frame(width: 800, height: 300)
}
