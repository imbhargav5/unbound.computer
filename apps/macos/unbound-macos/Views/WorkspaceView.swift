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

    // State
    @State private var isAddingRepository = false
    @State private var hasMigratedOrphans = false
    @State private var repositoryPendingRemoval: Repository?
    @State private var isRemovingRepository = false
    @State private var removeRepoError: String?

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
        guard let session = selectedSession else { return nil }

        // If session is a worktree, use its worktree path
        if session.isWorktree, let worktreePath = session.worktreePath {
            return worktreePath
        }

        // Otherwise use the repository path
        return selectedRepository?.path
    }

    /// Space needed for traffic lights (close, minimize, zoom)
    private let trafficLightWidth: CGFloat = 78

    /// Titlebar height (standard macOS titlebar)
    private let titlebarHeight: CGFloat = 28

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
                            }
                        )
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)

                        // Center - Chat Panel
                        if selectedSession != nil {
                            ChatPanel(
                                session: selectedSession,
                                repository: selectedRepository,
                                chatInput: $chatInput,
                                selectedModel: $selectedModel,
                                selectedThinkMode: $selectedThinkMode,
                                isPlanMode: $isPlanMode,
                                editorState: editorState
                            )
                            .frame(minWidth: 400)
                        } else {
                            WorkspaceEmptyState(
                                hasRepositories: !sessions.isEmpty,
                                onAddRepository: { addRepository() }
                            )
                            .frame(minWidth: 400)
                        }

                        // Right sidebar - Git Operations
                        RightSidebarPanel(
                            fileTreeViewModel: fileTreeViewModel,
                            gitViewModel: gitViewModel,
                            editorState: editorState,
                            selectedTab: $selectedSidebarTab,
                            workingDirectory: workingDirectoryPath
                        )
                        .frame(minWidth: 280, idealWidth: 400, maxWidth: 600)
                    }
                }
                .padding(.top, titlebarHeight)

                // Custom titlebar row (transparent, just for traffic lights spacing)
                WindowToolbar(content: {
                    Color.clear
                }, height: titlebarHeight)
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
        .task {
            await autoSelectFirstSessionIfNeeded()
        }
        .task {
            // Initialize FileTreeViewModel
            initializeFileTreeViewModelIfNeeded()
        }
        .onChange(of: selectedSession?.id) { _, newSessionId in
            fileTreeViewModel?.setSessionId(newSessionId)
            if selectedSidebarTab == .files {
                Task { await fileTreeViewModel?.loadRoot() }
            }
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
