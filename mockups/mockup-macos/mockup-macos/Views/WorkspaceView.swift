//
//  WorkspaceView.swift
//  mockup-macos
//
//  Shadcn-styled main workspace view.
//

import SwiftUI

struct WorkspaceView: View {
    @Environment(MockAppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    // Chat state
    @State private var chatInput: String = ""
    @State private var selectedModel: AIModel = .defaultModel
    @State private var selectedThinkMode: ThinkMode = .none
    @State private var isPlanMode: Bool = false

    // Version control state
    @State private var selectedSidebarTab: RightSidebarTab = .changes
    @State private var selectedTerminalTab: TerminalTab = .terminal

    private var colors: ThemeColors {
        ThemeColors(colorScheme)
    }

    // MARK: - Computed Properties

    /// Active sessions
    private var sessions: [Session] {
        appState.sessions.values.flatMap { $0 }
    }

    /// Selected session
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
                    // Mock add repository action
                },
                onCreateSessionForRepository: { _, _ in
                    // Mock create session action
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
                    onAddRepository: {}
                )
                .frame(minWidth: 400)
            }

            // Right sidebar - Git Operations
            RightSidebarPanel(
                selectedTab: $selectedSidebarTab,
                selectedTerminalTab: $selectedTerminalTab,
                workingDirectory: workingDirectoryPath
            )
            .frame(minWidth: 200, idealWidth: 300, maxWidth: 500)
        }
        .background(colors.background)
    }
}

#Preview {
    WorkspaceView()
        .environment(MockAppState())
        .frame(width: 1200, height: 800)
}
