//
//  RightSidebarPanel.swift
//  unbound-macos
//
//  Right panel with git operations: branch selector, commit/push actions,
//  and Changes/Files/Commits tabs.
//

import Logging
import SwiftUI

private let logger = Logger(label: "app.ui.sidebar")

// MARK: - Git Toolbar Action

private enum GitToolbarAction: Hashable {
    case commit
    case push

    var title: String {
        switch self {
        case .commit:
            return "Commit"
        case .push:
            return "Push"
        }
    }

    var systemImage: String {
        switch self {
        case .commit:
            return "checkmark.circle.fill"
        case .push:
            return "arrow.up.circle.fill"
        }
    }
}

private struct GitToolbarActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: GitToolbarAction
    let onTap: () -> Void

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var buttonBackground: Color {
        switch action {
        case .commit:
            return colors.success
        case .push:
            return colors.primaryAction
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: action.systemImage)
                    .font(.system(size: IconSize.xs))
                Text(action.title)
                    .font(Typography.toolbar)
            }
            .foregroundStyle(colors.primaryActionForeground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
    }
}

struct RightSidebarPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    // View models
    var fileTreeViewModel: FileTreeViewModel?
    @Bindable var gitViewModel: GitViewModel
    @Bindable var editorState: EditorState

    // State bindings
    @Binding var selectedTab: RightSidebarTab

    // Working directory
    let workingDirectory: String?

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var effectiveTab: RightSidebarTab {
        selectedTab == .spec ? .changes : selectedTab
    }

    private var bottomTabs: [RightSidebarTab] {
        [.changes, .files, .commits, .pullRequests]
    }

    private var currentLocalBranch: GitBranch? {
        if let currentName = gitViewModel.currentBranch,
           let branch = gitViewModel.localBranches.first(where: { $0.name == currentName }) {
            return branch
        }
        return gitViewModel.localBranches.first(where: { $0.isCurrent })
    }

    private var gitToolbarActions: [GitToolbarAction] {
        var actions: [GitToolbarAction] = []
        if !gitViewModel.stagedFiles.isEmpty {
            actions.append(.commit)
        }
        if let branch = currentLocalBranch,
           branch.upstream != nil,
           branch.ahead > 0 {
            actions.append(.push)
        }
        return actions
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            ShadcnDivider()
            errorBanner
            commitMessageInput
            bottomTabHeader
            ShadcnDivider()
            bottomTabContent
        }
        .background(colors.background)
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .files {
                Task { await fileTreeViewModel?.loadRoot() }
            }
        }
        .onChange(of: workingDirectory) { _, newPath in
            Task {
                await gitViewModel.setRepository(path: newPath)
            }
        }
        .onAppear {
            gitViewModel.setDaemonClient(appState.daemonClient)
            if selectedTab == .spec {
                selectedTab = .changes
            }
            Task {
                await gitViewModel.setRepository(path: workingDirectory)
                if selectedTab == .files {
                    await fileTreeViewModel?.loadRoot()
                }
            }
        }
    }

    // MARK: - Sidebar Header (branch left, git actions right)

    private var sidebarHeader: some View {
        HStack(spacing: Spacing.sm) {
            branchSelector

            Spacer()

            HStack(spacing: Spacing.xs) {
                ForEach(gitToolbarActions, id: \.self) { action in
                    GitToolbarActionButton(action: action, onTap: {
                        Task {
                            switch action {
                            case .commit:
                                await gitViewModel.commit()
                            case .push:
                                await gitViewModel.push()
                            }
                        }
                    })
                    .disabled(gitViewModel.isPerformingAction)
                }

                IconButton(systemName: "arrow.triangle.2.circlepath", action: {
                    Task { await gitViewModel.refreshAll() }
                })
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: LayoutMetrics.toolbarHeight)
        .background(colors.toolbarBackground)
    }

    // MARK: - Branch Selector

    private var branchSelector: some View {
        Button(action: {
            // Branch selection placeholder
        }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: IconSize.xs))
                Text(gitViewModel.currentBranch ?? "main")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .font(Typography.toolbar)
            .foregroundStyle(colors.mutedForeground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(colors.muted)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = gitViewModel.lastError {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: IconSize.xs))
                    .foregroundStyle(colors.destructive)
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(colors.destructive)
                    .lineLimit(2)
                Spacer()
                Button {
                    gitViewModel.lastError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundStyle(colors.mutedForeground)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xs)
            .background(colors.destructive.opacity(0.1))
        }
    }

    // MARK: - Commit Message Input

    @ViewBuilder
    private var commitMessageInput: some View {
        if !gitViewModel.stagedFiles.isEmpty {
            VStack(spacing: 0) {
                TextField("Commit message", text: Bindable(gitViewModel).commitMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: FontSize.sm, design: .monospaced))
                    .lineLimit(1...4)
                    .padding(Spacing.sm)
                    .background(colors.editorBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .stroke(colors.border, lineWidth: BorderWidth.hairline)
                    )
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
                ShadcnDivider()
            }
        }
    }

    // MARK: - Bottom Tab Header

    private var bottomTabHeader: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(bottomTabs) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: IconSize.xs))

                        Text(tab.rawValue)
                            .font(Typography.toolbarMuted)
                            .fontWeight(effectiveTab == tab ? .semibold : .regular)
                    }
                    .foregroundStyle(effectiveTab == tab ? colors.foreground : colors.mutedForeground)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .background(colors.background)
    }

    // MARK: - Bottom Tab Content

    @ViewBuilder
    private var bottomTabContent: some View {
        switch effectiveTab {
        case .changes:
            ChangesTabView(
                gitViewModel: gitViewModel,
                onFileSelected: { file in
                    selectFile(file)
                }
            )
        case .files:
            FilesTabView(
                fileTreeViewModel: fileTreeViewModel,
                onFileSelected: { file in
                    selectFile(file)
                }
            )
        case .commits:
            CommitsTabView(gitViewModel: gitViewModel)
        case .pullRequests:
            PullRequestsTabView(gitViewModel: gitViewModel)
        case .spec:
            ChangesTabView(
                gitViewModel: gitViewModel,
                onFileSelected: { file in
                    selectFile(file)
                }
            )
        }
    }

    // MARK: - Actions

    private func selectFile(_ file: GitStatusFile) {
        gitViewModel.selectFile(file.path)
        editorState.openDiffTab(relativePath: file.path)
        Task {
            await loadDiffForFile(file.path)
        }
    }

    private func selectFile(_ file: FileItem) {
        guard !file.isDirectory else { return }
        fileTreeViewModel?.selectFile(file.path)
        if let fullPath = resolveFullPath(for: file) {
            editorState.openFileTab(
                relativePath: file.path,
                fullPath: fullPath,
                sessionId: appState.selectedSessionId
            )
        }
    }

    private func resolveFullPath(for file: FileItem) -> String? {
        if file.path.hasPrefix("/") {
            return file.path
        }
        guard let workDir = workingDirectory else { return nil }
        return URL(fileURLWithPath: workDir).appendingPathComponent(file.path).path
    }

    private func loadDiffForFile(_ path: String) async {
        guard let workDir = workingDirectory else { return }

        editorState.setDiffLoading(for: path, isLoading: true)
        defer { editorState.setDiffLoading(for: path, isLoading: false) }

        do {
            let diffContent = try await appState.daemonClient.getGitDiff(path: workDir, filePath: path)
            if !diffContent.isEmpty {
                editorState.setDiff(for: path, diff: FileDiff.parse(from: diffContent, filePath: path))
            } else {
                editorState.setDiff(for: path, diff: nil)
            }
        } catch {
            logger.warning("Failed to load diff: \(error.localizedDescription)")
            editorState.setDiffError(for: path, message: error.localizedDescription)
        }
    }
}

private struct PullRequestsTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @Bindable var gitViewModel: GitViewModel

    @State private var showCreateForm = false
    @State private var deleteBranchOnMerge = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if showCreateForm {
                createForm
                ShadcnDivider()
            }

            if gitViewModel.isLoadingPullRequests {
                loadingView
            } else if gitViewModel.pullRequests.isEmpty {
                emptyView
            } else {
                listView
            }

            if let selected = gitViewModel.selectedPullRequest {
                ShadcnDivider()
                selectedPRFooter(selected)
            }
        }
        .task {
            if gitViewModel.pullRequests.isEmpty {
                await gitViewModel.refreshPullRequests()
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Button {
                showCreateForm.toggle()
            } label: {
                Label(showCreateForm ? "Close" : "Create PR", systemImage: showCreateForm ? "xmark" : "plus")
                    .font(Typography.toolbar)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Task { await gitViewModel.refreshPullRequests() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: IconSize.xs))
            }
            .buttonStyle(.plain)
            .disabled(gitViewModel.isLoadingPullRequests)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(colors.toolbarBackground)
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            TextField("PR title", text: Bindable(gitViewModel).prTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: Bindable(gitViewModel).prBody)
                .frame(height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(colors.border, lineWidth: BorderWidth.hairline)
                )

            HStack(spacing: Spacing.xs) {
                Button("Create") {
                    Task { await gitViewModel.createPullRequest() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(gitViewModel.prTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gitViewModel.isCreatingPullRequest)

                Button("Cancel") {
                    showCreateForm = false
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(gitViewModel.pullRequests) { pullRequest in
                    Button {
                        Task { await gitViewModel.selectPullRequest(pullRequest) }
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                Text("#\(pullRequest.number)")
                                    .font(.system(size: FontSize.xs, design: .monospaced))
                                    .foregroundStyle(colors.mutedForeground)
                                Text(pullRequest.title)
                                    .font(Typography.bodySmall)
                                    .foregroundStyle(colors.foreground)
                                    .lineLimit(1)
                                Spacer()
                                Text(pullRequest.state)
                                    .font(.system(size: FontSize.xs, design: .monospaced))
                                    .foregroundStyle(colors.mutedForeground)
                            }

                            if let mergeState = pullRequest.mergeStateStatus {
                                Text("merge: \(mergeState)")
                                    .font(.system(size: FontSize.xs, design: .monospaced))
                                    .foregroundStyle(colors.mutedForeground)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            gitViewModel.selectedPullRequest?.number == pullRequest.number
                                ? colors.selectionBackground
                                : colors.background
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .stroke(
                                    gitViewModel.selectedPullRequest?.number == pullRequest.number
                                        ? colors.selectionBorder
                                        : Color.clear,
                                    lineWidth: BorderWidth.hairline
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.xs)
        }
    }

    private func selectedPRFooter(_ pullRequest: GHPullRequest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Button("Open in GitHub") {
                    if let url = URL(string: pullRequest.url) {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Picker("Merge", selection: Bindable(gitViewModel).prMergeMethod) {
                    ForEach(GHPRMergeMethod.allCases, id: \.self) { method in
                        Text(method.rawValue.capitalized).tag(method)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }

            HStack(spacing: Spacing.xs) {
                Toggle("Delete branch", isOn: $deleteBranchOnMerge)
                    .toggleStyle(.checkbox)
                    .font(Typography.caption)

                Spacer()

                Button("Refresh Checks") {
                    Task { await gitViewModel.refreshSelectedPullRequestChecks() }
                }
                .buttonStyle(.bordered)
                .disabled(gitViewModel.isLoadingPullRequestChecks)

                Button("Merge") {
                    Task { await gitViewModel.mergeSelectedPullRequest(deleteBranch: deleteBranchOnMerge) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(gitViewModel.isMergingPullRequest)
            }

            if let checks = gitViewModel.selectedPullRequestChecks {
                Text("checks: \(checks.summary.passing) pass, \(checks.summary.failing) fail, \(checks.summary.pending) pending")
                    .font(.system(size: FontSize.xs, design: .monospaced))
                    .foregroundStyle(colors.mutedForeground)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Loading PRs...")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var emptyView: some View {
        VStack(spacing: Spacing.sm) {
            Text("No pull requests")
                .font(Typography.bodySmall)
                .foregroundStyle(colors.mutedForeground)
            Button("Refresh") {
                Task { await gitViewModel.refreshPullRequests() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// MARK: - Preview

#Preview("Changes Tab") {
    RightSidebarPanel(
        fileTreeViewModel: .preview(),
        gitViewModel: .preview(),
        editorState: .preview(),
        selectedTab: .constant(.changes),
        workingDirectory: "/Users/dev/Code/unbound.computer"
    )
    .frame(width: 300, height: 600)
}

#Preview("Commits Tab") {
    RightSidebarPanel(
        fileTreeViewModel: .preview(),
        gitViewModel: .preview(),
        editorState: .preview(),
        selectedTab: .constant(.commits),
        workingDirectory: "/Users/dev/Code/unbound.computer"
    )
    .frame(width: 300, height: 600)
}

#Preview("Files Tab") {
    RightSidebarPanel(
        fileTreeViewModel: .preview(),
        gitViewModel: .preview(withStatus: false),
        editorState: .preview(),
        selectedTab: .constant(.files),
        workingDirectory: "/Users/dev/Code/unbound.computer"
    )
    .frame(width: 300, height: 600)
}

#Preview("Empty State") {
    RightSidebarPanel(
        fileTreeViewModel: nil,
        gitViewModel: GitViewModel(),
        editorState: EditorState(),
        selectedTab: .constant(.changes),
        workingDirectory: "/Users/test/project"
    )
    .frame(width: 300, height: 600)
}
