//
//  FileChangeSummaryView.swift
//  unbound-macos
//
//  Grouped summary panel for file changes shown after assistant responses.
//

import SwiftUI

struct FileChangeSummaryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let fileChanges: [FileChange]

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var totalAdditions: Int {
        fileChanges.reduce(0) { $0 + $1.linesAdded }
    }

    private var totalDeletions: Int {
        fileChanges.reduce(0) { $0 + $1.linesRemoved }
    }

    private var headerTitle: String {
        let count = fileChanges.count
        return "\(count) file\(count == 1 ? "" : "s") changed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(Spacing.md)

            if !fileChanges.isEmpty {
                ShadcnDivider()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(fileChanges) { fileChange in
                        FileChangeSummaryRow(fileChange: fileChange)

                        if fileChange.id != fileChanges.last?.id {
                            ShadcnDivider()
                        }
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

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(headerTitle)
                .font(Typography.bodySmall)
                .foregroundStyle(colors.foreground)

            if totalAdditions > 0 || totalDeletions > 0 {
                HStack(spacing: Spacing.xs) {
                    if totalAdditions > 0 {
                        Text("+\(totalAdditions)")
                            .font(Typography.caption)
                            .foregroundStyle(colors.success)
                    }
                    if totalDeletions > 0 {
                        Text("-\(totalDeletions)")
                            .font(Typography.caption)
                            .foregroundStyle(colors.destructive)
                    }
                }
            }

            Spacer()

            Button(action: {}) {
                HStack(spacing: Spacing.xs) {
                    Text("Undo")
                    Image(systemName: "arrow.uturn.backward")
                }
                .font(Typography.caption)
                .foregroundStyle(colors.mutedForeground)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FileChangeSummaryRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let fileChange: FileChange

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(fileChange.filePath)
                .font(Typography.code)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if fileChange.linesAdded > 0 || fileChange.linesRemoved > 0 {
                HStack(spacing: Spacing.xs) {
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
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

#if DEBUG

#Preview {
    FileChangeSummaryView(fileChanges: [
        FileChange(filePath: "apps/macos/unbound-macos/Views/Workspace/RightSidebarPanel.swift", changeType: .modified, linesAdded: 2, linesRemoved: 2),
        FileChange(filePath: "apps/macos/unbound-macos/Views/Workspace/WorkspaceView.swift", changeType: .modified, linesAdded: 2, linesRemoved: 2),
        FileChange(filePath: "mockups/mockup-macos/mockup-macos/Views/Workspace/RightSidebarPanel.swift", changeType: .modified, linesAdded: 2, linesRemoved: 2)
    ])
    .frame(width: 520)
    .padding()
}

#endif
