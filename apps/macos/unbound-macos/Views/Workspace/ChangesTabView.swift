//
//  ChangesTabView.swift
//  unbound-macos
//
//  VS Code-style read-only file changes list.
//  Dense, monospace, single-line rows with +N/-N indicators.
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
            LazyVStack(alignment: .leading, spacing: 0) {
                if gitViewModel.isLoadingStatus {
                    loadingView
                } else if gitViewModel.isClean {
                    emptyStateView
                } else {
                    ForEach(allChangedFiles) { file in
                        VSCodeChangeRow(
                            file: file,
                            isSelected: gitViewModel.selectedFilePath == file.path,
                            onSelect: { onFileSelected(file) }
                        )
                    }
                }
            }
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

// MARK: - VS Code Style Change Row

/// A dense, single-line file change row styled like VS Code's Source Control.
/// Read-only, no actions - just displays file path and status indicator.
struct VSCodeChangeRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let file: GitStatusFile
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Status indicator letter (M, A, D, U)
                Text(file.status.indicator)
                    .font(GeistFont.mono(size: FontSize.xs, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: IconSize.sm)

                // File path (truncated from left if needed)
                Text(file.path)
                    .font(GeistFont.mono(size: FontSize.sm, weight: .regular))
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer(minLength: Spacing.sm)

                // Change stats (+N / -N) - VS Code style
                changeStats
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? colors.selectionBackground : (isHovered ? colors.hoverBackground : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .stroke(isSelected ? colors.selectionBorder : Color.clear, lineWidth: BorderWidth.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var changeStats: some View {
        HStack(spacing: Spacing.xs) {
            if let additions = file.additions, additions > 0 {
                Text("+\(additions)")
                    .font(GeistFont.mono(size: FontSize.xs, weight: .medium))
                    .foregroundStyle(colors.diffAddition)
            }
            if let deletions = file.deletions, deletions > 0 {
                Text("-\(deletions)")
                    .font(GeistFont.mono(size: FontSize.xs, weight: .medium))
                    .foregroundStyle(colors.diffDeletion)
            }
        }
    }

    private var statusColor: Color {
        file.status.color(colors)
    }
}

// MARK: - Preview

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
