//
//  WorkspaceView.swift
//  unbound-macos
//
//  Shadcn-styled main workspace view.
//  Delegates all business logic to daemon via AppState.
//

import AppKit
import Logging
import SwiftUI

private let logger = Logger(label: "app.ui")

struct WorkspaceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    // Chat state
    @State private var chatInput: String = ""
    @State private var selectedModel: AIModel = .opus
    @State private var selectedThinkMode: ThinkMode = .none
    @State private var isPlanMode: Bool = false

    // Version control state - ViewModel manages file tree
    @State private var fileTreeViewModel: FileTreeViewModel?
    @State private var gitViewModel = GitViewModel()
    @State private var selectedSidebarTab: RightSidebarTab = .changes
    @State private var editorState = EditorState()
    @State private var workspaceTabState = WorkspaceTabState()

    // State
    @State private var isAddingRepository = false
    @State private var hasMigratedOrphans = false
    @State private var repositoryPendingRemoval: Repository?
    @State private var isRemovingRepository = false
    @State private var removeRepoError: String?
    @State private var pendingCloseTabId: UUID?
    @State private var showUnsavedCloseDialog = false
    @State private var conflictTabId: UUID?
    @State private var conflictRevision: DaemonFileRevision?
    @State private var showConflictDialog = false

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    // MARK: - Computed Properties (from AppState cached daemon data)

    /// Active sessions (cached from daemon)
    private var sessions: [Session] {
        appState.sessions.values.flatMap { $0 }
    }

    /// Selected session (from AppState)
    private var selectedSession: Session? {
        appState.selectedSession
    }

    /// Get the repository for the selected session
    private var selectedRepository: Repository? {
        appState.selectedRepository
    }

    /// Get the working directory path for the selected session
    private var workingDirectoryPath: String? {
        resolvedWorkingDirectoryPath(for: selectedSession)
    }

    private var chromeHeight: CGFloat {
        appState.localSettings.isZenModeEnabled ? 28 : LayoutMetrics.compactToolbarHeight
    }

    private var shouldRenderCenterPanel: Bool {
        selectedSession != nil || !editorState.tabs.isEmpty || !workspaceTabState.terminalTabs.isEmpty
    }

    /// Commands available in the command palette
    private var commandPaletteCommands: [CommandItem] {
        [
            CommandItem(
                icon: "folder.badge.plus",
                title: "Add Repository",
                shortcut: "⌘⇧A"
            ) {
                addRepository()
            },
            CommandItem(
                icon: "gearshape",
                title: "Settings",
                shortcut: "⌘,"
            ) {
                appState.showSettings = true
            },
        ]
    }

    var body: some View {
        let removeDialogBinding = Binding<Bool>(
            get: { repositoryPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    repositoryPendingRemoval = nil
                    removeRepoError = nil
                }
            }
        )

        ZStack {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if appState.isGhInstalled == false {
                        GhMissingBanner()
                    }

                    HSplitView {
                        // Left sidebar - Sessions
                        if appState.localSettings.leftSidebarVisible {
                            WorkspacesSidebar(
                                onOpenSettings: {
                                    appState.showSettings = true
                                },
                                onAddRepository: {
                                    addRepository()
                                },
                                onCreateSessionForRepository: { repository, locationType in
                                    createSession(for: repository, locationType: locationType)
                                },
                                onRequestRemoveRepository: { repository in
                                    requestRemoveRepository(repository)
                                },
                                onCreateTerminalTab: { session in
                                    createTerminalTab(for: session)
                                }
                            )
                            .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                        }

                        // Center - Chat Panel
                        ZStack {
                            if shouldRenderCenterPanel {
                                ChatPanel(
                                    session: selectedSession,
                                    repository: selectedRepository,
                                    chatInput: $chatInput,
                                    selectedModel: $selectedModel,
                                    selectedThinkMode: $selectedThinkMode,
                                    isPlanMode: $isPlanMode,
                                    editorState: editorState,
                                    workspaceTabState: workspaceTabState
                                )
                            } else {
                                WorkspaceEmptyState(
                                    hasRepositories: !sessions.isEmpty,
                                    onAddRepository: { addRepository() }
                                )
                            }

                        }
                        .frame(minWidth: 400)

                        // Right sidebar - Git Operations
                        if appState.localSettings.rightSidebarVisible {
                            RightSidebarPanel(
                                fileTreeViewModel: fileTreeViewModel,
                                gitViewModel: gitViewModel,
                                editorState: editorState,
                                selectedTab: $selectedSidebarTab,
                                workingDirectory: workingDirectoryPath,
                                onOpenEditorTab: { tabId in
                                    workspaceTabState.selectEditor(tabId)
                                }
                            )
                            .frame(minWidth: 280, idealWidth: 400, maxWidth: 600)
                        }
                    }
                }
                .padding(.top, chromeHeight)

                // Top navbar or transparent titlebar (zen mode)
                if appState.localSettings.isZenModeEnabled {
                    WindowToolbar(content: { Color.clear }, height: 28)
                } else {
                    TopNavbar(
                        session: selectedSession,
                        editorState: editorState,
                        workspaceTabState: workspaceTabState,
                        onRequestCloseEditorTab: { tabId in
                            requestCloseEditorTab(tabId)
                        },
                        onRequestCloseTerminalTab: { tabId in
                            workspaceTabState.closeTerminalTab(tabId, editorTabIds: editorState.tabs.map(\.id))
                        },
                        onOpenSettings: { appState.showSettings = true }
                    )
                }
            }

            if appState.localSettings.isZenModeEnabled {
                Badge("Zen Mode", variant: .outline)
                    .help("Zen Mode — ⌘K Z")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, chromeHeight + Spacing.sm)
                    .padding(.trailing, Spacing.lg)
            }

            if appState.showCommandPalette {
                CommandPaletteOverlay(
                    isPresented: Binding(
                        get: { appState.showCommandPalette },
                        set: { appState.showCommandPalette = $0 }
                    ),
                    commands: commandPaletteCommands
                )
            }

            if let repository = repositoryPendingRemoval {
                RemoveRepositoryOverlay(
                    isPresented: removeDialogBinding,
                    repository: repository,
                    isRemoving: isRemovingRepository,
                    errorMessage: removeRepoError,
                    onConfirm: {
                        confirmRemoveRepository(repository)
                    }
                )
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
                    closeEditorTab(id: tabId)
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
        .background(colors.background)
        .background(WindowTitlebarConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .background(
            KeyboardShortcutHandler(
                key: "k",
                modifiers: .command
            ) {
                withAnimation(.easeOut(duration: Duration.fast)) {
                    appState.showCommandPalette.toggle()
                }
            }
        )
        .background(
            KeyboardShortcutHandler(
                key: "`",
                modifiers: .control
            ) {
                createTerminalTabForSelectedSession()
            }
        )
        .background(
            KeyboardShortcutSequenceHandler(
                firstKey: "k",
                firstModifiers: .command,
                secondKey: "z",
                secondModifiers: [],
                timeout: 1.2
            ) {
                withAnimation(.easeOut(duration: Duration.fast)) {
                    appState.localSettings.setZenModeEnabled(!appState.localSettings.isZenModeEnabled)
                }
            }
        )
        .task {
            await autoSelectFirstSessionIfNeeded()
        }
        .task {
            // Initialize FileTreeViewModel
            initializeFileTreeViewModelIfNeeded()
        }
        .task {
            syncWorkspaceTabState()
        }
        .onChange(of: selectedSession?.id) { _, newSessionId in
            Task { @MainActor in
                fileTreeViewModel?.setSessionId(newSessionId)
                if selectedSidebarTab == .files {
                    await fileTreeViewModel?.loadRoot()
                }
                syncWorkspaceTabState()
            }
        }
        .onChange(of: workingDirectoryPath) { _, _ in
            syncWorkspaceTabState()
        }
    }

    // MARK: - ViewModel Initialization

    private func initializeFileTreeViewModelIfNeeded() {
        guard fileTreeViewModel == nil else { return }
        fileTreeViewModel = FileTreeViewModel()
        fileTreeViewModel?.setSessionId(selectedSession?.id)
    }

    /// Auto-select first session if none is selected
    private func autoSelectFirstSessionIfNeeded() async {
        if appState.selectedSessionId == nil, let first = sessions.first {
            appState.selectSession(first.id)
        }
    }

    private func createSession(for repository: Repository, locationType: SessionLocationType) {
        Task {
            do {
                let session = try await appState.createSession(
                    repositoryId: repository.id,
                    title: "New conversation",
                    locationType: locationType
                )
                appState.selectSession(session.id)
            } catch {
                logger.error("Failed to create session: \(error)")
            }
        }
    }

    private func requestRemoveRepository(_ repository: Repository) {
        removeRepoError = nil
        repositoryPendingRemoval = repository
    }

    private func confirmRemoveRepository(_ repository: Repository) {
        guard !isRemovingRepository else { return }
        isRemovingRepository = true

        Task {
            do {
                try await appState.removeRepository(repository.id)
                repositoryPendingRemoval = nil
                removeRepoError = nil
            } catch {
                logger.error("Failed to remove repository: \(error)")
                removeRepoError = "Failed to remove repository. Please try again."
            }

            isRemovingRepository = false
        }
    }

    private func addRepository() {
        guard !isAddingRepository else { return }
        isAddingRepository = true

        Task {
            do {
                // Show folder picker
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = false
                panel.message = "Select a repository folder"
                panel.prompt = "Add Repository"

                let response = await panel.begin()
                if response == .OK, let url = panel.url {
                    let repository = try await appState.addRepository(path: url.path)
                    // Auto-create a session for the new repository
                    let session = try await appState.createSession(
                        repositoryId: repository.id,
                        title: "New conversation"
                    )
                    appState.selectSession(session.id)
                }
            } catch {
                logger.error("Failed to add repository: \(error)")
            }
            isAddingRepository = false
        }
    }

    private func syncWorkspaceTabState() {
        workspaceTabState.resetForSession(
            selectedSession?.id,
            workspacePath: workingDirectoryPath
        )
    }

    private func resolvedWorkingDirectoryPath(for session: Session?) -> String? {
        guard let session else { return nil }

        if session.isWorktree, let worktreePath = session.worktreePath {
            return FileManager.default.fileExists(atPath: worktreePath) ? worktreePath : nil
        }

        guard let repositoryPath = appState.repositories.first(where: { $0.id == session.repositoryId })?.path else {
            return nil
        }

        return FileManager.default.fileExists(atPath: repositoryPath) ? repositoryPath : nil
    }

    private func createTerminalTab(for session: Session) {
        appState.selectSession(session.id)
        _ = workspaceTabState.createTerminalTab(
            for: session.id,
            workspacePath: resolvedWorkingDirectoryPath(for: session)
        )
    }

    private func createTerminalTabForSelectedSession() {
        guard let session = selectedSession else { return }
        _ = workspaceTabState.createTerminalTab(
            for: session.id,
            workspacePath: workingDirectoryPath
        )
    }

    private func requestCloseEditorTab(_ tabId: UUID) {
        if editorState.isDirty(tabId: tabId) {
            pendingCloseTabId = tabId
            showUnsavedCloseDialog = true
            return
        }

        closeEditorTab(id: tabId)
    }

    private func closeEditorTab(id tabId: UUID) {
        editorState.closeTab(id: tabId)
        workspaceTabState.closeEditorTab(tabId, remainingEditorTabIds: editorState.tabs.map(\.id))
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
            case .saved, .noChanges:
                if closeOnSuccess {
                    closeEditorTab(id: tabId)
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
}

// MARK: - Keyboard Shortcut Handler

struct KeyboardShortcutHandler: NSViewRepresentable {
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.key = key
        view.modifiers = modifiers
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyCaptureView {
            view.action = action
        }
    }

    class KeyCaptureView: NSView {
        var key: String = ""
        var modifiers: NSEvent.ModifierFlags = []
        var action: (() -> Void)?

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }

                    let eventModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                    let requiredModifiers = self.modifiers.intersection([.command, .shift, .option, .control])

                    if event.charactersIgnoringModifiers?.lowercased() == self.key.lowercased(),
                       eventModifiers == requiredModifiers
                    {
                        self.action?()
                        return nil // Consume the event
                    }
                    return event
                }
            }
        }

        override func removeFromSuperview() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}

struct KeyboardShortcutSequenceHandler: NSViewRepresentable {
    let firstKey: String
    let firstModifiers: NSEvent.ModifierFlags
    let secondKey: String
    let secondModifiers: NSEvent.ModifierFlags
    let timeout: TimeInterval
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = SequenceKeyCaptureView()
        view.firstKey = firstKey
        view.firstModifiers = firstModifiers
        view.secondKey = secondKey
        view.secondModifiers = secondModifiers
        view.timeout = timeout
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? SequenceKeyCaptureView {
            view.action = action
            view.timeout = timeout
        }
    }

    class SequenceKeyCaptureView: NSView {
        var firstKey: String = ""
        var firstModifiers: NSEvent.ModifierFlags = []
        var secondKey: String = ""
        var secondModifiers: NSEvent.ModifierFlags = []
        var timeout: TimeInterval = 1.2
        var action: (() -> Void)?

        private var monitor: Any?
        private var awaitingSecondKey: Bool = false
        private var awaitingUntil: Date?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }

                    let eventModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                    let requiredFirstModifiers = self.firstModifiers.intersection([.command, .shift, .option, .control])
                    let requiredSecondModifiers = self.secondModifiers.intersection([.command, .shift, .option, .control])

                    if event.charactersIgnoringModifiers?.lowercased() == self.firstKey.lowercased(),
                       eventModifiers == requiredFirstModifiers
                    {
                        self.awaitingSecondKey = true
                        self.awaitingUntil = Date().addingTimeInterval(self.timeout)
                        return nil // Consume the event
                    }

                    if awaitingSecondKey {
                        let isWithinTimeout = awaitingUntil.map { Date() <= $0 } ?? false
                        if isWithinTimeout,
                           event.charactersIgnoringModifiers?.lowercased() == self.secondKey.lowercased(),
                           eventModifiers == requiredSecondModifiers
                        {
                            awaitingSecondKey = false
                            awaitingUntil = nil
                            action?()
                            return nil // Consume the event
                        }
                        awaitingSecondKey = false
                        awaitingUntil = nil
                    }

                    return event
                }
            }
        }

        override func removeFromSuperview() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}

#if DEBUG

#Preview("Populated Dashboard") {
    WorkspaceView()
        .environment(AppState.preview())
        .frame(width: 1200, height: 800)
}

#Preview("Empty") {
    WorkspaceView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}

#endif
