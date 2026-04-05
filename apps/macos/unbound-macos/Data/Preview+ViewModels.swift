//
//  Preview+ViewModels.swift
//  unbound-macos
//
//  Static factory extensions for creating pre-populated view models
//  and state objects for Xcode Canvas previews. Each factory calls
//  the corresponding configureForPreview() method defined in the
//  view model's own file.
//

#if DEBUG

import SwiftUI

// MARK: - GitViewModel + Preview

extension GitViewModel {
    /// A fully populated GitViewModel for Canvas previews.
    static func preview(
        branch: String = "main",
        withStatus: Bool = true,
        withCommits: Bool = true,
        withBranches: Bool = true
    ) -> GitViewModel {
        let vm = GitViewModel()
        vm.configureForPreview(
            repositoryPath: "/Users/dev/Code/unbound.computer",
            currentBranch: branch,
            status: withStatus ? PreviewData.gitStatus : nil,
            commits: withCommits ? PreviewData.commits : [],
            localBranches: withBranches ? PreviewData.localBranches : [],
            remoteBranches: withBranches ? PreviewData.remoteBranches : []
        )
        return vm
    }
}

// MARK: - EditorState + Preview

extension EditorState {
    /// An EditorState with open tabs and loaded content.
    static func preview() -> EditorState {
        let state = EditorState()
        state.configureForPreview(
            tabs: PreviewData.editorTabs,
            documentContent: PreviewData.sampleSwiftCode
        )
        return state
    }
}

// MARK: - FileTreeViewModel + Preview

extension FileTreeViewModel {
    /// A FileTreeViewModel with a pre-loaded file tree.
    static func preview() -> FileTreeViewModel {
        let vm = FileTreeViewModel()
        vm.configureForPreview(
            fileTree: PreviewData.fileTree,
            expandedPaths: [
                "apps",
                "apps/macos",
                "apps/macos/unbound-macos",
                "apps/macos/unbound-macos/Services",
                "docs",
            ]
        )
        return vm
    }
}

// MARK: - SessionLiveState + Preview

extension SessionLiveState {
    /// A SessionLiveState with messages, tool state, and history.
    static func preview(
        claudeRunning: Bool = false,
        withActiveTools: Bool = false,
        withMessages: Bool = true,
        runtimeStatus: RuntimeStatusEnvelope? = nil
    ) -> SessionLiveState {
        let state = SessionLiveState(sessionId: PreviewData.sessionId1)
        state.configureForPreview(
            messages: withMessages ? PreviewData.chatMessages : [],
            claudeRunning: claudeRunning,
            activeTools: withActiveTools ? PreviewData.activeTools : [],
            activeSubAgents: withActiveTools ? PreviewData.activeSubAgents : [],
            toolHistory: withMessages ? PreviewData.toolHistory : [],
            runtimeStatus: runtimeStatus
        )
        return state
    }

    /// A SessionLiveState showing Claude actively working with tools.
    static func previewActive() -> SessionLiveState {
        preview(claudeRunning: true, withActiveTools: true)
    }
}

// MARK: - AppState + Preview

extension AppState {
    /// A fully populated AppState for dashboard-level previews.
    /// Includes repositories, sessions, and a pre-configured SessionLiveState
    /// registered in the SessionStateManager for the selected session.
    static func preview(
        withSessionState: Bool = true,
        claudeRunning: Bool = false,
        runtimeStatus: RuntimeStatusEnvelope? = nil
    ) -> AppState {
        let state = AppState()
        state.configureForPreview(
            repositories: PreviewData.repositories,
            sessions: PreviewData.sessions,
            selectedRepositoryId: PreviewData.repoId1,
            selectedSessionId: PreviewData.sessionId1
        )

        // Register a pre-populated SessionLiveState so ChatPanel renders with messages
        if withSessionState {
            let sessionState = SessionLiveState.preview(
                claudeRunning: claudeRunning,
                withActiveTools: claudeRunning,
                runtimeStatus: runtimeStatus
            )
            state.sessionStateManager.registerForPreview(
                sessionId: PreviewData.sessionId1,
                state: sessionState
            )
        }

        return state
    }
}

#endif
