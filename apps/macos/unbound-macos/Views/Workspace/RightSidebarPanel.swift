//
//  RightSidebarPanel.swift
//  unbound-macos
//
//  Right panel with integrated file editor (top) and Changes/Files/Commits (bottom).
//  Matches design: file tabs + editor content + changes section in a single column.
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

    @State private var pendingCloseTabId: UUID?
    @State private var showUnsavedCloseDialog: Bool = false
    @State private var conflictTabId: UUID?
    @State private var conflictRevision: DaemonFileRevision?
    @State private var showConflictDialog: Bool = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    private var effectiveTab: RightSidebarTab {
        selectedTab == .spec ? .changes : selectedTab
    }

    private var bottomTabs: [RightSidebarTab] {
        [.changes, .files, .commits]
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

    /// Currently selected editor tab
    private var selectedEditorTab: EditorTab? {
        if let id = editorState.selectedTabId {
            return editorState.tabs.first { $0.id == id }
        }
        return editorState.tabs.first
    }

    private var selectedFileTab: EditorTab? {
        guard let tab = selectedEditorTab, tab.kind == .file else { return nil }
        return tab
    }

    private var dirtyTabIds: Set<UUID> {
        Set(
            editorState.documentsByTabId
                .filter { $0.value.isDirty }
                .map(\.key)
        )
    }

    private var canSaveSelectedFile: Bool {
        guard let selectedFileTab else { return false }
        return editorState.canSave(tabId: selectedFileTab.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            VSplitView {
                // Top section - File editor
                VStack(spacing: 0) {
                    FileEditorTabBar(
                        files: editorState.tabs,
                        dirtyTabIds: dirtyTabIds,
                        selectedFileId: editorState.selectedTabId ?? editorState.tabs.first?.id,
                        onSelectFile: { id in
                            editorState.selectTab(id: id)
                        },
                        onCloseFile: { id in
                            requestCloseTab(id)
                        }
                    ) {
                        HStack(spacing: Spacing.sm) {
                            branchSelector
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
                            saveButton
                        }
                    }

                    ShadcnDivider()

                    editorContent
                }
                .frame(minHeight: 200)
                .background(colors.editorBackground)

                // Bottom section - Changes/Files/Commits
                VStack(spacing: 0) {
                    changesHeader
                    errorBanner
                    ShadcnDivider()
                    commitMessageInput
                    bottomTabHeader
                    ShadcnDivider()
                    bottomTabContent
                }
                .frame(minHeight: 200)
            }
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
        .confirmationDialog(
            "Unsaved changes",
            isPresented: $showUnsavedCloseDialog,
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task { await saveAndClosePendingTab() }
            }
            Button("Discard", role: .destructive) {
                if let tabId = pendingCloseTabId {
                    editorState.closeTab(id: tabId)
                }
                pendingCloseTabId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCloseTabId = nil
            }
        } message: {
            Text("Save changes before closing this tab?")
        }
        .confirmationDialog(
            "File changed on disk",
            isPresented: $showConflictDialog,
            titleVisibility: .visible
        ) {
            Button("Reload") {
                guard let tabId = conflictTabId else { return }
                Task {
                    await editorState.reloadFile(tabId: tabId, daemonClient: appState.daemonClient)
                    clearConflictState()
                }
            }
            Button("Overwrite") {
                guard let tabId = conflictTabId else { return }
                Task {
                    await overwriteAfterConflict(tabId: tabId)
                }
            }
            Button("Cancel", role: .cancel) {
                clearConflictState()
            }
        } message: {
            if let revision = conflictRevision {
                Text("Current revision token: \(revision.token)")
            } else {
                Text("The file was modified externally. Reload or overwrite your local edits.")
            }
        }
    }

    // MARK: - Editor Content

    @ViewBuilder
    private var editorContent: some View {
        if let tab = selectedEditorTab {
            switch tab.kind {
            case .file:
                FileEditorView(tab: tab, editorState: editorState)
            case .diff:
                DiffEditorView(
                    path: tab.path,
                    diffState: editorState.diffStates[tab.path]
                )
            }
        } else {
            VStack(spacing: Spacing.md) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(colors.mutedForeground)

                Text("No file open")
                    .font(Typography.body)
                    .foregroundStyle(colors.mutedForeground)

                Text("Select a file from the chat or file tree")
                    .font(Typography.caption)
                    .foregroundStyle(colors.mutedForeground.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.editorBackground)
        }
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

    private var saveButton: some View {
        Button {
            Task { await saveActiveFile() }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: IconSize.xs))
                Text("Save")
                    .font(Typography.toolbar)
            }
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(colors.muted)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!canSaveSelectedFile)
        .opacity(canSaveSelectedFile ? 1.0 : 0.55)
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

    // MARK: - Changes Header

    private var changesHeader: some View {
        HStack(spacing: Spacing.sm) {
            Text("Changes")
                .font(Typography.toolbar)
                .foregroundStyle(colors.foreground)

            if gitViewModel.changesCount > 0 {
                Text("\(gitViewModel.changesCount)")
                    .font(Typography.micro)
                    .foregroundStyle(colors.mutedForeground)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(colors.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .stroke(colors.border, lineWidth: BorderWidth.hairline)
                    )
            }

            Spacer()

            IconButton(systemName: "arrow.triangle.2.circlepath", action: {
                Task { await gitViewModel.refreshAll() }
            })
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: LayoutMetrics.toolbarHeight)
        .background(colors.toolbarBackground)
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

    private func requestCloseTab(_ tabId: UUID) {
        if editorState.isDirty(tabId: tabId) {
            pendingCloseTabId = tabId
            showUnsavedCloseDialog = true
            return
        }
        editorState.closeTab(id: tabId)
    }

    private func saveActiveFile() async {
        guard let tab = selectedFileTab else { return }
        await performSave(
            tabId: tab.id,
            forceOverwrite: false,
            closeOnSuccess: false
        )
    }

    private func saveAndClosePendingTab() async {
        guard let tabId = pendingCloseTabId else { return }
        await performSave(
            tabId: tabId,
            forceOverwrite: false,
            closeOnSuccess: true
        )
    }

    private func overwriteAfterConflict(tabId: UUID) async {
        let shouldCloseAfterSave = pendingCloseTabId == tabId
        await performSave(
            tabId: tabId,
            forceOverwrite: true,
            closeOnSuccess: shouldCloseAfterSave
        )
        clearConflictState()
    }

    private func performSave(
        tabId: UUID,
        forceOverwrite: Bool,
        closeOnSuccess: Bool
    ) async {
        do {
            let outcome = try await editorState.saveFile(
                tabId: tabId,
                daemonClient: appState.daemonClient,
                forceOverwrite: forceOverwrite
            )
            switch outcome {
            case .saved:
                if closeOnSuccess {
                    editorState.closeTab(id: tabId)
                }
                pendingCloseTabId = nil
            case .noChanges:
                if closeOnSuccess {
                    editorState.closeTab(id: tabId)
                }
                pendingCloseTabId = nil
            case .conflict(let currentRevision):
                conflictTabId = tabId
                conflictRevision = currentRevision
                showConflictDialog = true
            }
        } catch {
            logger.warning("Save failed: \(error.localizedDescription)")
        }
    }

    private func clearConflictState() {
        conflictTabId = nil
        conflictRevision = nil
        showConflictDialog = false
        pendingCloseTabId = nil
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
