//
//  ChangesTabView.swift
//  unbound-macos
//
//  Git changes tab showing staged and unstaged files.
//

import SwiftUI

struct ChangesTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var gitViewModel: GitViewModel
    var onFileSelected: (GitStatusFile) -> Void

    @State private var stagedExpanded = true
    @State private var unstagedExpanded = true
    @State private var untrackedExpanded = true

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if gitViewModel.isLoadingStatus {
                    loadingView
                } else if gitViewModel.isClean {
                    emptyStateView
                } else {
                    // Staged section
                    if !gitViewModel.stagedFiles.isEmpty {
                        ChangesSection(
                            title: "Staged Changes",
                            count: gitViewModel.stagedFiles.count,
                            isExpanded: $stagedExpanded,
                            headerAction: {
                                Task { await gitViewModel.unstageAll() }
                            },
                            headerActionIcon: "minus.circle",
                            headerActionTooltip: "Unstage All"
                        ) {
                            ForEach(gitViewModel.stagedFiles) { file in
                                ChangeFileRow(
                                    file: file,
                                    isSelected: gitViewModel.selectedFilePath == file.path,
                                    onSelect: { onFileSelected(file) },
                                    onStageToggle: {
                                        Task { await gitViewModel.unstageFiles([file.path]) }
                                    },
                                    stageAction: .unstage
                                )
                            }
                        }
                    }

                    // Unstaged section (modified files)
                    if !gitViewModel.unstagedFiles.isEmpty {
                        ChangesSection(
                            title: "Changes",
                            count: gitViewModel.unstagedFiles.count,
                            isExpanded: $unstagedExpanded,
                            headerAction: {
                                let paths = gitViewModel.unstagedFiles.map { $0.path }
                                Task { await gitViewModel.stageFiles(paths) }
                            },
                            headerActionIcon: "plus.circle",
                            headerActionTooltip: "Stage All"
                        ) {
                            ForEach(gitViewModel.unstagedFiles) { file in
                                ChangeFileRow(
                                    file: file,
                                    isSelected: gitViewModel.selectedFilePath == file.path,
                                    onSelect: { onFileSelected(file) },
                                    onStageToggle: {
                                        Task { await gitViewModel.stageFiles([file.path]) }
                                    },
                                    onDiscard: {
                                        Task { await gitViewModel.discardChanges([file.path]) }
                                    },
                                    stageAction: .stage
                                )
                            }
                        }
                    }

                    // Untracked section
                    if !gitViewModel.untrackedFiles.isEmpty {
                        ChangesSection(
                            title: "Untracked",
                            count: gitViewModel.untrackedFiles.count,
                            isExpanded: $untrackedExpanded,
                            headerAction: {
                                let paths = gitViewModel.untrackedFiles.map { $0.path }
                                Task { await gitViewModel.stageFiles(paths) }
                            },
                            headerActionIcon: "plus.circle",
                            headerActionTooltip: "Stage All"
                        ) {
                            ForEach(gitViewModel.untrackedFiles) { file in
                                ChangeFileRow(
                                    file: file,
                                    isSelected: gitViewModel.selectedFilePath == file.path,
                                    onSelect: { onFileSelected(file) },
                                    onStageToggle: {
                                        Task { await gitViewModel.stageFiles([file.path]) }
                                    },
                                    stageAction: .stage
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Loading changes...")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: IconSize.xxxl))
                .foregroundStyle(colors.success)

            Text("Working directory clean")
                .font(Typography.body)
                .foregroundStyle(colors.foreground)

            Text("No uncommitted changes")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Changes Section

struct ChangesSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    var headerAction: (() -> Void)?
    var headerActionIcon: String = "plus.circle"
    var headerActionTooltip: String = ""
    @ViewBuilder let content: () -> Content

    @State private var isHeaderHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: Spacing.sm) {
                Button {
                    withAnimation(.easeInOut(duration: Duration.default)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.sm)

                        Text(title)
                            .font(Typography.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(colors.mutedForeground)
                            .textCase(.uppercase)

                        Text("\(count)")
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(colors.muted)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Header action button (appears on hover)
                if let action = headerAction, isHeaderHovered {
                    Button(action: action) {
                        Image(systemName: headerActionIcon)
                            .font(.system(size: IconSize.sm))
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .help(headerActionTooltip)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHeaderHovered = hovering
            }

            // Content
            if isExpanded {
                content()
            }
        }
    }
}

// MARK: - Change File Row

enum StageAction {
    case stage
    case unstage
}

struct ChangeFileRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let file: GitStatusFile
    let isSelected: Bool
    var onSelect: () -> Void
    var onStageToggle: () -> Void
    var onDiscard: (() -> Void)?
    let stageAction: StageAction

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                // Status indicator
                Text(file.status.indicator)
                    .font(Typography.mono)
                    .foregroundStyle(file.status.color)
                    .frame(width: IconSize.md, alignment: .center)

                // File name and directory
                VStack(alignment: .leading, spacing: 0) {
                    Text(file.fileName)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    if !file.directory.isEmpty {
                        Text(file.directory)
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Action buttons (appear on hover)
                if isHovered {
                    HStack(spacing: Spacing.xs) {
                        // Discard button (only for unstaged)
                        if let discard = onDiscard {
                            Button(action: discard) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: IconSize.xs))
                                    .foregroundStyle(colors.destructive)
                            }
                            .buttonStyle(.plain)
                            .help("Discard Changes")
                        }

                        // Stage/Unstage button
                        Button(action: onStageToggle) {
                            Image(systemName: stageAction == .stage ? "plus" : "minus")
                                .font(.system(size: IconSize.xs))
                                .foregroundStyle(colors.mutedForeground)
                        }
                        .buttonStyle(.plain)
                        .help(stageAction == .stage ? "Stage" : "Unstage")
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected ? colors.accent : (isHovered ? colors.muted : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: Duration.fast)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChangesTabView(
        gitViewModel: GitViewModel(),
        onFileSelected: { _ in }
    )
    .frame(width: 280, height: 400)
}
