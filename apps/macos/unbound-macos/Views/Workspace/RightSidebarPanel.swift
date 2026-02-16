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
        [.changes, .files, .commits]
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            ShadcnDivider()
            errorBanner
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

    // MARK: - Sidebar Header (layout toggle + branch left, commit right)

    private var sidebarHeader: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                layoutTogglePill
                branchPill
            }

            Spacer()

            if !gitViewModel.stagedFiles.isEmpty {
                commitSplitButton
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: 48)
        .background(colors.toolbarBackground)
    }

    // MARK: - Layout Toggle Pill

    private var layoutTogglePill: some View {
        Button {
            withAnimation(.easeOut(duration: Duration.fast)) {
                appState.localSettings.rightSidebarVisible = false
            }
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: IconSize.md))
                .foregroundStyle(colors.mutedForeground)
                .padding(6)
                .background(colors.secondary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(colors.borderInput, lineWidth: BorderWidth.default)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Branch Pill

    private var branchPill: some View {
        Button(action: {
            // Branch selection placeholder
        }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: IconSize.md))
                    .foregroundStyle(colors.mutedForeground)
                Text(gitViewModel.currentBranch ?? "main")
                    .font(GeistFont.sans(size: FontSize.smMd, weight: .medium))
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(Color(hex: "777777"))
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background(colors.secondary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(colors.borderInput, lineWidth: BorderWidth.default)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Commit Split Button

    private var commitSplitButton: some View {
        HStack(spacing: 0) {
            Button {
                Task { await gitViewModel.commit() }
            } label: {
                Text("Commit")
                    .font(GeistFont.sans(size: FontSize.sm, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, Spacing.md)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 20)
                .background(Color(hex: "2ECC71"))

            Button {
                // Commit dropdown options placeholder
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: IconSize.sm))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, Spacing.sm)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 32)
        .background(colors.success)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .disabled(gitViewModel.isPerformingAction)
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

    // MARK: - Bottom Tab Header

    private var bottomTabHeader: some View {
        HStack(spacing: Spacing.lg) {
            ForEach(bottomTabs) { tab in
                let isActive = effectiveTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: IconSize.sm))
                                .foregroundStyle(isActive ? colors.primary : colors.inactive)

                            Text(tab.rawValue)
                                .font(isActive ? Typography.captionMedium : Typography.caption)
                                .foregroundStyle(isActive ? colors.foreground : colors.sidebarMeta)

                            if isActive, tab == .changes, gitViewModel.changesCount > 0 {
                                Text("\(gitViewModel.changesCount)")
                                    .font(GeistFont.sans(size: 9, weight: .medium))
                                    .foregroundStyle(colors.primary)
                                    .padding(.vertical, 1)
                                    .padding(.horizontal, 5)
                                    .background(colors.accentAmberSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.lg)
                                            .strokeBorder(colors.accentAmberBorder, lineWidth: BorderWidth.default)
                                    )
                            }
                        }
                        .frame(height: 34)

                        Rectangle()
                            .fill(isActive ? colors.primary : Color.clear)
                            .frame(height: BorderWidth.thick)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: 36)
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
        case .pullRequests, .spec:
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
                                    .font(GeistFont.mono(size: FontSize.xs, weight: .regular))
                                    .foregroundStyle(colors.mutedForeground)
                                Text(pullRequest.title)
                                    .font(Typography.bodySmall)
                                    .foregroundStyle(colors.foreground)
                                    .lineLimit(1)
                                Spacer()
                                Text(pullRequest.state)
                                    .font(GeistFont.mono(size: FontSize.xs, weight: .regular))
                                    .foregroundStyle(colors.mutedForeground)
                            }

                            if let mergeState = pullRequest.mergeStateStatus {
                                Text("merge: \(mergeState)")
                                    .font(GeistFont.mono(size: FontSize.xs, weight: .regular))
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
                    .font(GeistFont.mono(size: FontSize.xs, weight: .regular))
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
