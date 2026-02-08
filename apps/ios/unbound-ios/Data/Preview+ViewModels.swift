//
//  Preview+ViewModels.swift
//  unbound-ios
//
//  Static factory extensions for creating pre-populated view models
//  and state objects for Xcode Canvas previews. Each factory calls
//  the corresponding configureForPreview() method defined in the
//  view model's own file.
//

#if DEBUG

import SwiftUI

// MARK: - ChatViewModel + Preview

extension ChatViewModel {
    /// A fully populated ChatViewModel for Canvas previews.
    static func preview(
        withMessages: Bool = true,
        withSessions: Bool = false,
        isTyping: Bool = false,
        withToolState: Bool = false,
        withMCQ: Bool = false
    ) -> ChatViewModel {
        let vm = ChatViewModel()
        vm.configureForPreview(
            messages: withMessages ? PreviewData.messages : [],
            isTyping: isTyping,
            sessions: withSessions ? PreviewData.activeSessions : [],
            currentToolState: withToolState ? PreviewData.activeToolState : nil,
            completedTools: withToolState ? PreviewData.toolHistory : []
        )
        return vm
    }

    /// A ChatViewModel showing a rich conversation with MCQ, tool use, and code diffs.
    static func previewRich() -> ChatViewModel {
        let vm = ChatViewModel()
        vm.configureForPreview(
            messages: PreviewData.richMessages,
            sessions: PreviewData.activeSessions
        )
        return vm
    }

    /// A ChatViewModel showing Claude actively working with tools.
    static func previewActive() -> ChatViewModel {
        let vm = ChatViewModel()
        vm.configureForPreview(
            messages: PreviewData.messages,
            isTyping: true,
            sessions: PreviewData.activeSessions,
            currentToolState: PreviewData.activeToolState,
            completedTools: PreviewData.toolHistory
        )
        return vm
    }

    /// An empty ChatViewModel for "new chat" previews.
    static func previewEmpty() -> ChatViewModel {
        ChatViewModel()
    }
}

// MARK: - ActiveSessionManager + Preview

extension ActiveSessionManager {
    /// A session manager pre-populated with active sessions.
    static func preview(
        withSessions: Bool = true
    ) -> ActiveSessionManager {
        let manager = ActiveSessionManager()
        if withSessions {
            manager.configureForPreview(sessions: PreviewData.activeSessions)
        }
        return manager
    }
}

#endif
