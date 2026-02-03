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
        ZStack {
            ZStack(alignment: .top) {
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
                        }
                    )
                    .frame(minWidth: 120, idealWidth: 168, maxWidth: 240)

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
                    .frame(minWidth: 250, idealWidth: 450)
                }
                .padding(.top, titlebarHeight)

                // Custom titlebar row (same line as traffic lights)
                WindowToolbar(content: {
                    ZStack {
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: trafficLightWidth)
                            Spacer()
                        }

                        Button {
                            withAnimation(.easeOut(duration: Duration.fast)) {
                                appState.showCommandPalette = true
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: IconSize.xs))
                                    .foregroundStyle(colors.mutedForeground)

                                Text("Search...")
                                    .font(Typography.caption)
                                    .foregroundStyle(colors.mutedForeground)

                                Spacer()

                                Text("⌘K")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(colors.mutedForeground.opacity(0.7))
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, 2)
                                    .background(colors.muted)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                            }
                            .frame(width: 200)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(colors.muted.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .stroke(colors.border.opacity(0.3), lineWidth: BorderWidth.hairline)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, Spacing.lg)
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

#Preview {
    WorkspaceView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}
