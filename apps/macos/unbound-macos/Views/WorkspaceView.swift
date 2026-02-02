//
//  WorkspaceView.swift
//  unbound-macos
//
//  Shadcn-styled main workspace view.
//  Delegates all business logic to daemon via AppState.
//

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
    @State private var selectedTerminalTab: TerminalTab = .terminal

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

    var body: some View {
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
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)

            // Center - Chat Panel
            if selectedSession != nil {
                ChatPanel(
                    session: selectedSession,
                    repository: selectedRepository,
                    chatInput: $chatInput,
                    selectedModel: $selectedModel,
                    selectedThinkMode: $selectedThinkMode,
                    isPlanMode: $isPlanMode
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
                selectedTab: $selectedSidebarTab,
                selectedTerminalTab: $selectedTerminalTab,
                workingDirectory: workingDirectoryPath
            )
            .frame(minWidth: 200, idealWidth: 300, maxWidth: 500)
        }
        .background(colors.background)
        .task {
            await autoSelectFirstSessionIfNeeded()
        }
        .task {
            // Initialize FileTreeViewModel
            initializeFileTreeViewModelIfNeeded()
        }
        .task(id: workingDirectoryPath) {
            await loadFileTree()
        }
    }

    // MARK: - ViewModel Initialization

    private func initializeFileTreeViewModelIfNeeded() {
        guard fileTreeViewModel == nil else { return }
        fileTreeViewModel = FileTreeViewModel(
            fileSystemService: FileSystemService()
        )
    }

    /// Auto-select first session if none is selected
    private func autoSelectFirstSessionIfNeeded() async {
        if appState.selectedSessionId == nil, let first = sessions.first {
            appState.selectSession(first.id)
        }
    }

    private func loadFileTree() async {
        guard let path = workingDirectoryPath else {
            fileTreeViewModel?.clearFileTree()
            return
        }

        await fileTreeViewModel?.loadFileTree(at: path)
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

#Preview {
    WorkspaceView()
        .environment(AppState())
        .frame(width: 1200, height: 800)
}
