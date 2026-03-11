//
//  RightSidebarPanel.swift
//  unbound-macos
//
//  Right panel with git operations: branch selector, commit/push actions,
//  and Changes/Files/Commits tabs.
//

import Logging
import OpenTelemetryApi
import SwiftUI

private let logger = Logger(label: "app.ui.sidebar")

struct RightSidebarPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    // View models
    var fileTreeViewModel: FileTreeViewModel?
    @Bindable var gitViewModel: GitViewModel
    @Bindable var editorState: EditorState

    // State bindings
    @Binding var selectedTab: RightSidebarTab

    // Working directory
    let workingDirectory: String?
    var onOpenEditorTab: ((UUID) -> Void)? = nil

    // Header action state
    @State private var isCommitDropdownOpen = false
    @State private var isPushDropdownOpen = false
    @State private var hoveredDropdownItem: String?
    @State private var isDispatchingAgentAction = false

    private enum HeaderPrimaryActionMode: Equatable {
        case commit
        case push
        case disabledCommit
    }

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var effectiveTab: RightSidebarTab {
        selectedTab == .spec ? .changes : selectedTab
    }

    private var bottomTabs: [RightSidebarTab] {
        [.changes, .files, .commits]
    }

    private var selectedSessionLiveState: SessionLiveState? {
        guard let session = appState.selectedSession else { return nil }
        return appState.sessionStateManager.stateIfExists(for: session.id)
    }

    private var isSelectedSessionStreaming: Bool {
        selectedSessionLiveState?.codingSessionStatus.isStreaming ?? false
    }

    private var canDispatchGitAgentAction: Bool {
        guard appState.selectedSession != nil else { return false }
        guard let workingDirectory, !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !isDispatchingAgentAction && !gitViewModel.isPerformingAction && !isSelectedSessionStreaming
    }

    private var headerPrimaryActionMode: HeaderPrimaryActionMode {
        if gitViewModel.hasUncommittedChanges {
            return .commit
        }
        if gitViewModel.hasUnpushedCommits {
            return .push
        }
        return .disabledCommit
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
        .onChange(of: headerPrimaryActionMode) { _, _ in
            isCommitDropdownOpen = false
            isPushDropdownOpen = false
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard oldPhase != .active, newPhase == .active else { return }
            Task {
                await refreshSidebarOnAppReactivationIfNeeded()
            }
        }
        .onChange(of: isSelectedSessionStreaming) { wasStreaming, isStreaming in
            guard wasStreaming && !isStreaming else { return }
            Task { await gitViewModel.refreshAll() }
        }
        .onChange(of: workingDirectory) { _, newPath in
            Task {
                await gitViewModel.setRepository(path: newPath)
            }
        }
        .onAppear {
            Task { @MainActor in
                gitViewModel.setDaemonClient(appState.daemonClient)
                if selectedTab == .spec {
                    selectedTab = .changes
                }
                await gitViewModel.setRepository(path: workingDirectory)
                if selectedTab == .files {
                    await fileTreeViewModel?.loadRoot()
                }
            }
        }
    }

    private func refreshSidebarOnAppReactivationIfNeeded() async {
        guard let workingDirectory,
              !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard appState.isDaemonConnected else { return }

        let tab = effectiveTab
        guard gitViewModel.canRefreshSidebarData(for: tab) else { return }

        await gitViewModel.refreshSidebarData(for: tab)
    }

    // MARK: - Sidebar Header (branch left, commit right)

    private var sidebarHeader: some View {
        HStack(spacing: Spacing.sm) {
            branchPill

            Spacer()

            headerActionControl
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: 48)
        .background(colors.toolbarBackground)
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

    // MARK: - Header Actions

    private var isGHAuthenticated: Bool {
        guard let auth = gitViewModel.ghAuthStatus else { return false }
        return auth.authenticatedHostCount > 0
    }

    private var isCommitDisabled: Bool {
        !gitViewModel.hasUncommittedChanges || !canDispatchGitAgentAction
    }

    private var isPushDisabled: Bool {
        !gitViewModel.hasUnpushedCommits || !canDispatchGitAgentAction
    }

    @ViewBuilder
    private var headerActionControl: some View {
        switch headerPrimaryActionMode {
        case .commit:
            commitSplitButton(disabled: isCommitDisabled)
        case .push:
            pushSplitButton(disabled: isPushDisabled)
        case .disabledCommit:
            commitSplitButton(disabled: true)
        }
    }

    private func commitSplitButton(disabled: Bool) -> some View {
        let enabledBg = Color(hex: "22C55E")
        let disabledBg = Color(hex: "1F3D2A")

        return HStack(spacing: 0) {
            Button {
                dispatchGitAgentAction(.commit)
            } label: {
                Text("Commit")
                    .font(GeistFont.sans(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(disabled ? 0.5 : 1))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .disabled(disabled)

            Rectangle()
                .fill(Color(hex: "2ECC71"))
                .frame(width: 1)
                .padding(.vertical, 6)
                .opacity(disabled ? 0.5 : 1)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPushDropdownOpen = false
                    isCommitDropdownOpen.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(disabled ? 0.5 : 1))
                    .rotationEffect(.degrees(isCommitDropdownOpen ? 180 : 0))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .popover(isPresented: $isCommitDropdownOpen, arrowEdge: .bottom) {
                commitDropdownMenu
            }
        }
        .frame(height: 32)
        .background(disabled ? disabledBg.opacity(0.6) : enabledBg)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
        )
    }

    private func pushSplitButton(disabled: Bool) -> some View {
        let enabledBg = Color(hex: "22C55E")
        let disabledBg = Color(hex: "1F3D2A")

        return HStack(spacing: 0) {
            Button {
                dispatchGitAgentAction(.push)
            } label: {
                Text("Push")
                    .font(GeistFont.sans(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(disabled ? 0.5 : 1))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .disabled(disabled)

            Rectangle()
                .fill(Color(hex: "2ECC71"))
                .frame(width: 1)
                .padding(.vertical, 6)
                .opacity(disabled ? 0.5 : 1)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCommitDropdownOpen = false
                    isPushDropdownOpen.toggle()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(disabled ? 0.5 : 1))
                    .rotationEffect(.degrees(isPushDropdownOpen ? 180 : 0))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .popover(isPresented: $isPushDropdownOpen, arrowEdge: .bottom) {
                pushDropdownMenu
            }
        }
        .frame(height: 32)
        .background(disabled ? disabledBg.opacity(0.6) : enabledBg)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
        )
    }

    private var commitDropdownMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            commitDropdownItem(
                icon: "arrow.up",
                label: "Commit + Push",
                id: "commit-push",
                disabled: isCommitDisabled
            ) {
                isCommitDropdownOpen = false
                dispatchGitAgentAction(.commitAndPush)
            }

            commitDropdownItem(
                icon: "arrow.triangle.2.circlepath",
                label: "Commit + Rebase & Push",
                id: "commit-rebase-push",
                disabled: isCommitDisabled
            ) {
                isCommitDropdownOpen = false
                dispatchGitAgentAction(.commitRebaseAndPush)
            }

            commitDropdownItem(
                icon: "arrow.triangle.pull",
                label: "Commit + Create Pull Request",
                id: "commit-pr",
                disabled: isCommitDisabled || !isGHAuthenticated
            ) {
                isCommitDropdownOpen = false
                dispatchGitAgentAction(.commitAndCreatePullRequest)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 240)
        .background(Color(hex: "1A1A1A"))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(hex: "2A2A2A"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, y: 4)
    }

    private var pushDropdownMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            commitDropdownItem(
                icon: "arrow.triangle.2.circlepath",
                label: "Rebase & Push",
                id: "rebase-push",
                disabled: isPushDisabled
            ) {
                isPushDropdownOpen = false
                dispatchGitAgentAction(.rebaseAndPush)
            }

            commitDropdownItem(
                icon: "arrow.triangle.pull",
                label: "Create Pull Request",
                id: "push-pr",
                disabled: isPushDisabled || !isGHAuthenticated
            ) {
                isPushDropdownOpen = false
                dispatchGitAgentAction(.createPullRequest)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .background(Color(hex: "1A1A1A"))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(hex: "2A2A2A"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, y: 4)
    }

    private func commitDropdownItem(
        icon: String,
        label: String,
        id: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "A3A3A3").opacity(disabled ? 0.4 : 1))
                    .frame(width: 14, height: 14)
                Text(label)
                    .font(GeistFont.sans(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "E5E5E5").opacity(disabled ? 0.4 : 1))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                hoveredDropdownItem == id && !disabled
                    ? Color(hex: "2A2A2A")
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered in
            hoveredDropdownItem = isHovered ? id : nil
        }
    }

    private func dispatchGitAgentAction(_ action: GitSidebarAgentAction) {
        guard !isDispatchingAgentAction else { return }
        guard let session = appState.selectedSession else {
            gitViewModel.lastError = "Select a coding session before running Git actions."
            return
        }
        guard let workspacePath = workingDirectory,
              !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            gitViewModel.lastError = "Open a repository workspace before running Git actions."
            return
        }
        guard canDispatchGitAgentAction else {
            gitViewModel.lastError = "Git actions are unavailable while the session agent is busy."
            return
        }

        let liveState = appState.sessionStateManager.state(for: session.id)
        let prompt = GitAgentPromptFactory.prompt(for: action)

        isDispatchingAgentAction = true
        gitViewModel.lastError = nil

        Task { @MainActor in
            await liveState.sendMessage(
                prompt,
                session: session,
                workspacePath: workspacePath,
                modelIdentifier: nil,
                isPlanMode: false
            )

            if liveState.showErrorAlert {
                let message = liveState.errorAlertMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                if !message.isEmpty {
                    gitViewModel.lastError = message
                }
            }

            isDispatchingAgentAction = false
        }
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
        HStack(spacing: 16) {
            ForEach(bottomTabs) { tab in
                let isActive = effectiveTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 12))
                                .foregroundStyle(isActive ? .white : Color(hex: "5A5A5A"))

                            Text(tab.rawValue)
                                .font(GeistFont.sans(size: 11, weight: isActive ? .medium : .regular))
                                .foregroundStyle(isActive ? .white : Color(hex: "6B6B6B"))

                            if tab == .changes, gitViewModel.changesCount > 0 {
                                Text("\(gitViewModel.changesCount)")
                                    .font(GeistFont.sans(size: 9, weight: .regular))
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 1)
                                    .padding(.horizontal, 5)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxHeight: .infinity)

                        Rectangle()
                            .fill(isActive ? .white : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .frame(height: 32)
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
        let tabId = editorState.openDiffTab(relativePath: file.path)
        onOpenEditorTab?(tabId)
        Task {
            await loadDiffForFile(file.path)
        }
    }

    private func selectFile(_ file: FileItem) {
        guard !file.isDirectory else { return }
        fileTreeViewModel?.selectFile(file.path)
        if let fullPath = resolveFullPath(for: file) {
            let tabId = editorState.openFileTab(
                relativePath: file.path,
                fullPath: fullPath,
                sessionId: appState.selectedSessionId
            )
            onOpenEditorTab?(tabId)
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
            try await TracingService.withUserIntentRootIfNeeded(
                name: "git.diff_file",
                attributes: [
                    "repository.path_hash": .string(TracingService.hashIdentifier(workDir) ?? ""),
                    "repository.relative_path_hash": .string(TracingService.hashIdentifier(path) ?? "")
                ]
            ) { _ in
                let diffContent = try await appState.daemonClient.getGitDiff(path: workDir, filePath: path)
                if !diffContent.isEmpty {
                    editorState.setDiff(for: path, diff: FileDiff.parse(from: diffContent, filePath: path))
                } else {
                    editorState.setDiff(for: path, diff: nil)
                }
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

#if DEBUG

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

#endif
