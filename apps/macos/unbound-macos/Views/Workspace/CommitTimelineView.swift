//
//  CommitTimelineView.swift
//  unbound-macos
//
//  Read-only Git commit timeline view with VS Code / GitHub Desktop polish.
//  Supports selection for inspection only — no mutating actions.
//

import SwiftUI

// MARK: - Timeline View

struct CommitTimelineView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var gitViewModel: GitViewModel

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Branch selector
            branchSelector

            ShadcnDivider()

            // Timeline content
            if gitViewModel.isLoadingCommits && gitViewModel.commits.isEmpty {
                loadingView
            } else if gitViewModel.commits.isEmpty {
                emptyStateView
            } else {
                timelineList
            }
        }
    }

    // MARK: - Branch Selector

    private var branchSelector: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: IconSize.sm))
                .foregroundStyle(colors.mutedForeground)

            Menu {
                // Current branch section
                if let current = gitViewModel.currentBranch {
                    Button {
                        Task { await gitViewModel.selectBranch(nil) }
                    } label: {
                        HStack {
                            Text(current)
                            if gitViewModel.selectedBranch == nil {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()
                }

                // Local branches
                if !gitViewModel.localBranches.isEmpty {
                    Section("Local Branches") {
                        ForEach(gitViewModel.localBranches) { branch in
                            Button {
                                Task { await gitViewModel.selectBranch(branch.name) }
                            } label: {
                                HStack {
                                    Text(branch.name)
                                    if gitViewModel.selectedBranch == branch.name {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                // Remote branches
                if !gitViewModel.remoteBranches.isEmpty {
                    Divider()
                    Section("Remote Branches") {
                        ForEach(gitViewModel.remoteBranches) { branch in
                            Button {
                                Task { await gitViewModel.selectBranch(branch.name) }
                            } label: {
                                HStack {
                                    Text(branch.displayName)
                                    if gitViewModel.selectedBranch == branch.name {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text(gitViewModel.selectedBranch ?? gitViewModel.currentBranch ?? "Select branch")
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: IconSize.xs))
                        .foregroundStyle(colors.mutedForeground)
                }
            }
            .menuStyle(.borderlessButton)

            Spacer()

            // Loading indicator for branch switch
            if gitViewModel.isLoadingCommits && !gitViewModel.commits.isEmpty {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(gitViewModel.commitGraph.enumerated()), id: \.element.id) { index, node in
                    CommitTimelineRow(
                        node: node,
                        index: index,
                        totalCount: gitViewModel.commitGraph.count,
                        isSelected: gitViewModel.selectedCommitOid == node.commit.oid,
                        isFirst: index == 0,
                        isLast: index == gitViewModel.commitGraph.count - 1 && !gitViewModel.hasMoreCommits,
                        onSelect: {
                            gitViewModel.selectCommit(node.commit.oid)
                        }
                    )
                }

                // Load more indicator
                if gitViewModel.hasMoreCommits {
                    loadMoreButton
                }
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await gitViewModel.loadMoreCommits() }
        } label: {
            HStack(spacing: Spacing.sm) {
                // Continue timeline line
                TimelineConnector(isLoading: gitViewModel.isLoadingCommits)
                    .frame(width: TimelineConstants.columnWidth)

                if gitViewModel.isLoadingCommits {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text("Load more commits")
                        .font(Typography.bodySmall)
                }

                Spacer()
            }
            .padding(.vertical, Spacing.md)
            .foregroundStyle(colors.mutedForeground)
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Loading commits...")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: IconSize.xxxl))
                .foregroundStyle(colors.mutedForeground)

            Text("No commits")
                .font(Typography.body)
                .foregroundStyle(colors.foreground)

            Text("This branch has no commit history")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Timeline Constants

private enum TimelineConstants {
    static let columnWidth: CGFloat = 28
    static let lineWidth: CGFloat = 1.5
    static let nodeRadius: CGFloat = 4
    static let nodeStrokeWidth: CGFloat = 1.5
    static let rowHeight: CGFloat = 52
}

// MARK: - Timeline Row

private struct CommitTimelineRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let node: CommitGraphNode
    let index: Int
    let totalCount: Int
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    /// Progressive opacity fade for older commits
    private var temporalOpacity: Double {
        if index == 0 { return 1.0 }
        let fadeStart = 0.85
        let fadeEnd = 0.5
        let fadeRange = min(Double(index) / 20.0, 1.0)
        return fadeStart - (fadeStart - fadeEnd) * fadeRange
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 0) {
                // Timeline node column
                TimelineNode(
                    isFirst: isFirst,
                    isLast: isLast,
                    isMerge: node.commit.isMergeCommit,
                    isSelected: isSelected,
                    isHovered: isHovered
                )
                .frame(width: TimelineConstants.columnWidth)
                .frame(height: TimelineConstants.rowHeight)

                // Commit content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    // Commit message (primary)
                    Text(node.commit.summary)
                        .font(Typography.bodySmall)
                        .fontWeight(isFirst ? .medium : .regular)
                        .foregroundStyle(colors.foreground.opacity(temporalOpacity))
                        .lineLimit(1)

                    // Metadata row
                    HStack(spacing: Spacing.sm) {
                        // Short hash (monospace)
                        Text(node.commit.shortOid)
                            .font(Typography.mono)
                            .foregroundStyle(colors.info.opacity(temporalOpacity))

                        // Relative time
                        Text(node.commit.relativeTime)
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground.opacity(temporalOpacity))

                        Spacer()

                        // Author (de-emphasized, shows on hover or for first commit)
                        if isFirst || isHovered {
                            Text(node.commit.authorName)
                                .font(Typography.micro)
                                .foregroundStyle(colors.mutedForeground.opacity(temporalOpacity * 0.8))
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                }
                .padding(.vertical, Spacing.sm)
                .padding(.trailing, Spacing.md)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(backgroundColor)
                    .padding(.leading, TimelineConstants.columnWidth - Spacing.xs)
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

    private var backgroundColor: Color {
        if isSelected {
            return colors.accent
        } else if isHovered {
            return colors.muted.opacity(0.5)
        }
        return Color.clear
    }
}

// MARK: - Timeline Node

private struct TimelineNode: View {
    @Environment(\.colorScheme) private var colorScheme

    let isFirst: Bool
    let isLast: Bool
    let isMerge: Bool
    let isSelected: Bool
    let isHovered: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var lineColor: Color {
        colors.mutedForeground.opacity(0.3)
    }

    private var nodeColor: Color {
        if isFirst {
            return colors.success
        } else if isMerge {
            return colors.info
        }
        return colors.mutedForeground.opacity(0.6)
    }

    var body: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            let centerY = size.height / 2

            // Draw vertical line (above node)
            if !isFirst {
                var pathAbove = Path()
                pathAbove.move(to: CGPoint(x: centerX, y: 0))
                pathAbove.addLine(to: CGPoint(x: centerX, y: centerY - TimelineConstants.nodeRadius - 2))
                context.stroke(pathAbove, with: .color(lineColor), lineWidth: TimelineConstants.lineWidth)
            }

            // Draw vertical line (below node)
            if !isLast {
                var pathBelow = Path()
                pathBelow.move(to: CGPoint(x: centerX, y: centerY + TimelineConstants.nodeRadius + 2))
                pathBelow.addLine(to: CGPoint(x: centerX, y: size.height))
                context.stroke(pathBelow, with: .color(lineColor), lineWidth: TimelineConstants.lineWidth)
            }

            // Draw node circle
            let nodeRect = CGRect(
                x: centerX - TimelineConstants.nodeRadius,
                y: centerY - TimelineConstants.nodeRadius,
                width: TimelineConstants.nodeRadius * 2,
                height: TimelineConstants.nodeRadius * 2
            )

            if isFirst {
                // Filled circle for HEAD/newest
                context.fill(Circle().path(in: nodeRect), with: .color(nodeColor))
            } else {
                // Outlined circle for history
                context.stroke(
                    Circle().path(in: nodeRect),
                    with: .color(nodeColor),
                    lineWidth: TimelineConstants.nodeStrokeWidth
                )
            }

            // Merge indicator (double ring)
            if isMerge && !isFirst {
                let outerRect = nodeRect.insetBy(dx: -3, dy: -3)
                context.stroke(
                    Circle().path(in: outerRect),
                    with: .color(colors.info.opacity(0.4)),
                    lineWidth: 1
                )
            }
        }
    }
}

// MARK: - Timeline Connector (for load more)

private struct TimelineConnector: View {
    @Environment(\.colorScheme) private var colorScheme

    let isLoading: Bool

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        Canvas { context, size in
            let centerX = size.width / 2

            // Dashed line indicating "more commits"
            var path = Path()
            path.move(to: CGPoint(x: centerX, y: 0))
            path.addLine(to: CGPoint(x: centerX, y: size.height))

            context.stroke(
                path,
                with: .color(colors.mutedForeground.opacity(0.3)),
                style: StrokeStyle(
                    lineWidth: TimelineConstants.lineWidth,
                    dash: [4, 4]
                )
            )
        }
        .frame(height: 32)
    }
}

// MARK: - Preview

#Preview {
    CommitTimelineView(gitViewModel: GitViewModel())
        .frame(width: 320, height: 500)
}
