//
//  ChangesTabView.swift
//  unbound-macos
//
//  Compact file changes list matching Pencil design spec.
//  Filename-first layout with status indicator and diff stats.
//

import SwiftUI

struct ChangesTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var gitViewModel: GitViewModel
    var onFileSelected: (GitStatusFile) -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// All changed files combined (staged + unstaged + untracked)
    private var allChangedFiles: [GitStatusFile] {
        gitViewModel.stagedFiles + gitViewModel.unstagedFiles + gitViewModel.untrackedFiles
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if gitViewModel.isLoadingStatus {
                    loadingView
                } else if gitViewModel.isClean {
                    emptyStateView
                } else {
                    ForEach(allChangedFiles) { file in
                        ChangeRow(
                            file: file,
                            isSelected: gitViewModel.selectedFilePath == file.path,
                            onSelect: { onFileSelected(file) }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Loading...")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.sm) {
            Text("No changes")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Change Row

private struct ChangeRow: View {
    let file: GitStatusFile
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Status indicator letter (M, A, D, U)
                Text(file.status.indicator)
                    .font(GeistFont.sans(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)

                // Filename first, then directory path
                pathView
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Diff stats (+N / -N)
                diffStats
            }
            .padding(.horizontal, 16)
            .frame(height: 24)
            .background(isSelected ? Color(hex: "F59E0B").opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pathView: some View {
        let components = file.path.split(separator: "/", omittingEmptySubsequences: true)
        let fileName = String(components.last ?? Substring(file.path))
        let dirPath: String

        if components.count <= 1 {
            dirPath = ""
        } else {
            let fullDir = components.dropLast().joined(separator: "/") + "/"
            if fullDir.count > 30, components.count > 2 {
                let topFolder = String(components.first!)
                let parentFolder = String(components[components.count - 2])
                dirPath = "\(topFolder)/.../\(parentFolder)/"
            } else {
                dirPath = fullDir
            }
        }

        return HStack(spacing: 8) {
            Text(fileName)
                .font(GeistFont.sans(size: 11, weight: .regular))
                .foregroundStyle(Color(hex: "B3B3B3"))
            if !dirPath.isEmpty {
                Text(dirPath)
                    .font(GeistFont.sans(size: 11, weight: .regular))
                    .foregroundStyle(Color(hex: "666666"))
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var diffStats: some View {
        HStack(spacing: 6) {
            if let additions = file.additions {
                Text("+\(additions)")
                    .font(GeistFont.sans(size: 10, weight: .regular))
                    .foregroundStyle(Color(hex: "73C991"))
            }
            if let deletions = file.deletions {
                Text("-\(deletions)")
                    .font(GeistFont.sans(size: 10, weight: .regular))
                    .foregroundStyle(Color(hex: "F14C4C"))
            }
        }
    }

    private var statusColor: Color {
        switch file.status {
        case .modified, .renamed, .copied, .typechange:
            return Color(hex: "E2C08D")
        case .added, .untracked:
            return Color(hex: "73C991")
        case .deleted:
            return Color(hex: "F14C4C")
        case .conflicted, .unreadable:
            return Color(hex: "F14C4C")
        case .ignored, .unchanged:
            return Color(hex: "666666")
        }
    }
}

// MARK: - Preview

#if DEBUG

#Preview("With Changes") {
    ChangesTabView(
        gitViewModel: .preview(),
        onFileSelected: { _ in }
    )
    .frame(width: 280, height: 400)
}

#Preview("Empty") {
    ChangesTabView(
        gitViewModel: GitViewModel(),
        onFileSelected: { _ in }
    )
    .frame(width: 280, height: 400)
}

#endif
