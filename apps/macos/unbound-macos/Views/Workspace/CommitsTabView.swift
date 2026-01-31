//
//  CommitsTabView.swift
//  unbound-macos
//
//  Commits tab showing git commit history with graph visualization.
//

import SwiftUI

struct CommitsTabView: View {
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

            // Commit list
            if gitViewModel.isLoadingCommits && gitViewModel.commits.isEmpty {
                loadingView
            } else if gitViewModel.commits.isEmpty {
                emptyStateView
            } else {
                commitList
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

    // MARK: - Commit List

    private var commitList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(gitViewModel.commitGraph) { node in
                    CommitRow(
                        node: node,
                        isSelected: gitViewModel.selectedCommitOid == node.commit.oid,
                        onSelect: {
                            gitViewModel.selectCommit(node.commit.oid)
                        }
                    )
                }

                // Load more indicator
                if gitViewModel.hasMoreCommits {
                    Button {
                        Task { await gitViewModel.loadMoreCommits() }
                    } label: {
                        HStack {
                            Spacer()
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
            }
        }
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

// MARK: - Commit Row

struct CommitRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let node: CommitGraphNode
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private let graphWidth: CGFloat = 32
    private let nodeRadius: CGFloat = 4
    private let lineWidth: CGFloat = 2

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 0) {
                // Graph visualization
                graphView
                    .frame(width: graphWidth)

                // Commit info
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    // Summary
                    Text(node.commit.summary)
                        .font(Typography.bodySmall)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)

                    // Metadata
                    HStack(spacing: Spacing.sm) {
                        // Short OID
                        Text(node.commit.shortOid)
                            .font(Typography.mono)
                            .foregroundStyle(colors.info)

                        // Author
                        Text(node.commit.authorName)
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)

                        Spacer()

                        // Time
                        Text(node.commit.relativeTime)
                            .font(Typography.micro)
                            .foregroundStyle(colors.mutedForeground)
                    }
                }
                .padding(.vertical, Spacing.sm)
                .padding(.trailing, Spacing.md)
            }
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

    // MARK: - Graph View

    private var graphView: some View {
        Canvas { context, size in
            let centerX = size.width / 2 + CGFloat(node.column) * 12
            let centerY = size.height / 2

            // Draw vertical line continuing from above
            if !node.startsNewLine {
                var path = Path()
                path.move(to: CGPoint(x: centerX, y: 0))
                path.addLine(to: CGPoint(x: centerX, y: centerY - nodeRadius))
                context.stroke(path, with: .color(graphLineColor), lineWidth: lineWidth)
            }

            // Draw lines to parents (below)
            for connection in node.parentConnections {
                let fromX = centerX
                let toX = size.width / 2 + CGFloat(connection.toColumn) * 12

                var path = Path()
                path.move(to: CGPoint(x: fromX, y: centerY + nodeRadius))

                if fromX != toX {
                    // Diagonal line for branch/merge
                    path.addLine(to: CGPoint(x: toX, y: size.height))
                } else {
                    // Straight line
                    path.addLine(to: CGPoint(x: fromX, y: size.height))
                }

                let lineColor = connection.isMerge ? mergeLineColor : graphLineColor
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
            }

            // Draw node circle
            let nodeRect = CGRect(
                x: centerX - nodeRadius,
                y: centerY - nodeRadius,
                width: nodeRadius * 2,
                height: nodeRadius * 2
            )

            let nodeColor = node.commit.isMergeCommit ? mergeNodeColor : primaryNodeColor
            context.fill(Circle().path(in: nodeRect), with: .color(nodeColor))
            context.stroke(Circle().path(in: nodeRect), with: .color(colors.background), lineWidth: 1)
        }
        .frame(height: 44)
    }

    private var graphLineColor: Color {
        colors.mutedForeground.opacity(0.5)
    }

    private var mergeLineColor: Color {
        colors.info.opacity(0.5)
    }

    private var primaryNodeColor: Color {
        colors.success
    }

    private var mergeNodeColor: Color {
        colors.info
    }
}

// MARK: - Preview

#Preview {
    CommitsTabView(gitViewModel: GitViewModel())
        .frame(width: 300, height: 500)
}
