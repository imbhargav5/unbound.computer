//
//  CommitsTabView.swift
//  unbound-macos
//
//  Commits tab showing git commit history.
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
            branchSelector
            ShadcnDivider()

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
                ForEach(Array(gitViewModel.commitGraph.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Rectangle()
                            .fill(Color(hex: "1A1A1A"))
                            .frame(height: 1)
                    }

                    CommitRow(
                        node: node,
                        isSelected: gitViewModel.selectedCommitOid == node.commit.oid,
                        onSelect: {
                            gitViewModel.selectCommit(node.commit.oid)
                        }
                    )
                }

                if gitViewModel.hasMoreCommits {
                    Rectangle()
                        .fill(Color(hex: "1A1A1A"))
                        .frame(height: 1)

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
                                    .font(GeistFont.sans(size: 11, weight: .regular))
                                    .foregroundStyle(Color(hex: "555555"))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
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
    let node: CommitGraphNode
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                // Git commit icon
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(Color(hex: "888888"))
                    .frame(width: 16, height: 16)

                // Body: message + meta
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.commit.summary)
                        .font(GeistFont.sans(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "CCCCCC"))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Text(node.commit.shortOid)
                            .font(GeistFont.mono(size: 11, weight: .regular))
                            .foregroundStyle(Color(hex: "888888"))

                        Text(node.commit.relativeTime)
                            .font(GeistFont.sans(size: 11, weight: .regular))
                            .foregroundStyle(Color(hex: "555555"))
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG

#Preview("With Commits") {
    CommitsTabView(gitViewModel: .preview())
        .frame(width: 300, height: 500)
}

#Preview("Empty") {
    CommitsTabView(gitViewModel: GitViewModel())
        .frame(width: 300, height: 500)
}

#endif
