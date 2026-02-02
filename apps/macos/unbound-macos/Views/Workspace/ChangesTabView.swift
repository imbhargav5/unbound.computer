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

/// A collapsible section header for grouping files by status.
/// Design principles:
/// - Clear hierarchy with section title, count badge, and optional status summary
/// - Hover reveals bulk actions (stage all, unstage all)
/// - Smooth expand/collapse animations
struct ChangesSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    var headerAction: (() -> Void)?
    var headerActionIcon: String = "plus.circle"
    var headerActionTooltip: String = ""
    /// Optional status summary (e.g., file type breakdown)
    var statusSummary: [GitFileStatusType: Int]?
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
                        // Chevron indicator
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: IconSize.xs, weight: .semibold))
                            .foregroundStyle(colors.mutedForeground)
                            .frame(width: IconSize.sm)

                        // Section title
                        Text(title)
                            .font(Typography.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(colors.mutedForeground)
                            .textCase(.uppercase)

                        // Count badge
                        Text("\(count)")
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(colors.muted)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                        // Status breakdown badges (optional)
                        if let summary = statusSummary, !summary.isEmpty {
                            statusBreakdown(summary)
                        }
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

    /// Mini status breakdown showing count per status type
    /// e.g., [3M] [2A] [1D] in their respective colors
    @ViewBuilder
    private func statusBreakdown(_ summary: [GitFileStatusType: Int]) -> some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(Array(summary.keys.sorted { $0.rawValue < $1.rawValue }), id: \.self) { status in
                if let statusCount = summary[status], statusCount > 0 {
                    HStack(spacing: 1) {
                        Text("\(statusCount)")
                            .font(.system(size: FontSize.xxs, weight: .medium, design: .monospaced))
                        Text(status.indicator)
                            .font(.system(size: FontSize.xxs, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(statusColor(for: status))
                }
            }
        }
    }

    private func statusColor(for status: GitFileStatusType) -> Color {
        switch status {
        case .added: return colors.success
        case .modified: return colors.warning
        case .deleted: return colors.destructive
        case .renamed: return colors.info
        default: return colors.mutedForeground
        }
    }
}

// MARK: - Change File Row

enum StageAction {
    case stage
    case unstage
}

/// A single file row in the Changes tab.
/// Design principles:
/// - Status visible at a glance (<200ms recognition)
/// - Git-standard visual metaphors (not custom icons)
/// - Color-coded: Green=Added, Yellow=Modified, Red=Deleted, Gray=Untracked
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
                // Status indicator: colored badge with Git letter code
                // This is the primary visual signal - must be instantly recognizable
                statusBadge

                // File name and directory path
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
                    actionButtons
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

    // MARK: - Status Badge

    /// Git-standard status badge with letter indicator and semantic color.
    /// Examples: [M] yellow, [A] green, [D] red, [?] gray
    @ViewBuilder
    private var statusBadge: some View {
        let statusColor = semanticStatusColor

        Text(file.status.indicator)
            .font(.system(size: FontSize.xs, weight: .semibold, design: .monospaced))
            .foregroundStyle(statusColor)
            .frame(width: IconSize.lg, height: IconSize.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(statusColor.opacity(0.15))
            )
    }

    /// Semantic color based on ThemeColors for consistency
    private var semanticStatusColor: Color {
        switch file.status {
        case .added:
            return colors.success
        case .modified:
            return colors.warning
        case .deleted:
            return colors.destructive
        case .renamed, .copied:
            return colors.info
        case .untracked:
            return colors.mutedForeground
        case .conflicted:
            return colors.destructive
        default:
            return colors.mutedForeground
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: Spacing.xs) {
            // Discard button (only for unstaged modified/deleted files)
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
                Image(systemName: stageAction == .stage ? "plus.circle" : "minus.circle")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(colors.mutedForeground)
            }
            .buttonStyle(.plain)
            .help(stageAction == .stage ? "Stage" : "Unstage")
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
