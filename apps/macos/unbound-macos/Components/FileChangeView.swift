//
//  FileChangeView.swift
//  unbound-macos
//
//  Display file changes with type indicators
//

import SwiftUI

struct FileChangeView: View {
    @Environment(\.colorScheme) private var colorScheme

    let fileChange: FileChange
    @State private var isExpanded = false
    @State private var parsedDiff: FileDiff?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.md) {
                // File icon
                Image(systemName: fileIcon)
                    .font(.system(size: IconSize.md))
                    .foregroundStyle(changeTypeColor)

                // File path
                Text(fileChange.filePath)
                    .font(Typography.code)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Change type badge
                Text(changeTypeName)
                    .font(Typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(changeTypeColor)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(changeTypeColor.opacity(0.1))
                    )

                // Stats
                if fileChange.linesAdded > 0 || fileChange.linesRemoved > 0 {
                    HStack(spacing: Spacing.sm) {
                        if fileChange.linesAdded > 0 {
                            Text("+\(fileChange.linesAdded)")
                                .font(Typography.caption)
                                .foregroundStyle(colors.success)
                        }
                        if fileChange.linesRemoved > 0 {
                            Text("-\(fileChange.linesRemoved)")
                                .font(Typography.caption)
                                .foregroundStyle(colors.destructive)
                        }
                    }
                }

                // Expand button (if diff available)
                if fileChange.diff != nil {
                    Button {
                        withAnimation(.easeInOut(duration: Duration.fast)) {
                            isExpanded.toggle()
                            if isExpanded && parsedDiff == nil {
                                parseDiff()
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.md)

            // Diff view (if expanded)
            if isExpanded, let diff = fileChange.diff {
                ShadcnDivider()

                if let parsed = parsedDiff, !parsed.hunks.isEmpty {
                    // Use DiffViewer for parsed diffs
                    ScrollView {
                        UnifiedDiffView(hunks: parsed.hunks)
                    }
                    .frame(maxHeight: 300)
                } else {
                    // Fallback to raw text if parsing fails
                    ScrollView {
                        Text(diff)
                            .font(Typography.code)
                            .foregroundStyle(colors.foreground)
                            .textSelection(.enabled)
                            .padding(Spacing.md)
                    }
                    .frame(maxHeight: 200)
                    .background(colors.muted)
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

    private func parseDiff() {
        guard let rawDiff = fileChange.diff else { return }
        parsedDiff = DiffParser.parseFileDiff(rawDiff, filePath: fileChange.filePath)
    }

    private var fileIcon: String {
        switch fileChange.changeType {
        case .created: return "doc.badge.plus"
        case .modified: return "doc.badge.ellipsis"
        case .deleted: return "doc.badge.minus"
        case .renamed: return "arrow.right.doc.on.clipboard"
        }
    }

    private var changeTypeName: String {
        switch fileChange.changeType {
        case .created: return "Created"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        }
    }

    private var changeTypeColor: Color {
        switch fileChange.changeType {
        case .created: return colors.success
        case .modified: return colors.warning
        case .deleted: return colors.destructive
        case .renamed: return colors.info
        }
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        FileChangeView(fileChange: FileChange(
            filePath: "src/components/Button.swift",
            changeType: .modified,
            linesAdded: 15,
            linesRemoved: 3
        ))

        FileChangeView(fileChange: FileChange(
            filePath: "src/services/NewService.swift",
            changeType: .created,
            linesAdded: 42,
            linesRemoved: 0
        ))

        FileChangeView(fileChange: FileChange(
            filePath: "src/utils/deprecated.swift",
            changeType: .deleted,
            linesAdded: 0,
            linesRemoved: 28
        ))
    }
    .frame(width: 500)
    .padding()
}
