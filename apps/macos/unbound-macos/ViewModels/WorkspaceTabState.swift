//
//  WorkspaceTabState.swift
//  unbound-macos
//
//  Shared tab state for the workspace navbar.
//

import Foundation

enum WorkspaceTabSelection: Equatable {
    case conversation
    case terminal(UUID)
    case editor(UUID)
}

struct WorkspaceTerminalTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var workingDirectory: String
}

@MainActor
@Observable
final class WorkspaceTabState {
    private(set) var sessionId: UUID?
    private(set) var workspacePath: String?
    private(set) var terminalTabs: [WorkspaceTerminalTab] = []
    private(set) var terminalTabSequence: Int = 0

    var selection: WorkspaceTabSelection = .conversation

    func resetForSession(_ sessionId: UUID?, workspacePath: String?) {
        let isSameSession = self.sessionId == sessionId
        self.sessionId = sessionId
        self.workspacePath = workspacePath

        guard isSameSession else {
            terminalTabs.removeAll()
            terminalTabSequence = 0
            selection = .conversation
            return
        }

        guard let workspacePath else {
            terminalTabs.removeAll()
            terminalTabSequence = 0
            if case .terminal = selection {
                selection = .conversation
            }
            return
        }

        terminalTabs = terminalTabs.map { tab in
            var updated = tab
            updated.workingDirectory = workspacePath
            return updated
        }
    }

    @discardableResult
    func createTerminalTab(for sessionId: UUID?, workspacePath: String?) -> WorkspaceTerminalTab? {
        if self.sessionId != sessionId {
            resetForSession(sessionId, workspacePath: workspacePath)
        } else {
            self.workspacePath = workspacePath
        }

        guard let workspacePath else { return nil }

        terminalTabSequence += 1
        let tab = WorkspaceTerminalTab(
            id: UUID(),
            title: "Terminal \(terminalTabSequence)",
            workingDirectory: workspacePath
        )
        terminalTabs.append(tab)
        selection = .terminal(tab.id)
        return tab
    }

    func selectConversation() {
        selection = .conversation
    }

    func selectTerminal(_ tabId: UUID) {
        guard terminalTabs.contains(where: { $0.id == tabId }) else { return }
        selection = .terminal(tabId)
    }

    func selectEditor(_ tabId: UUID) {
        selection = .editor(tabId)
    }

    func closeTerminalTab(_ tabId: UUID, editorTabIds: [UUID]) {
        guard let closingIndex = terminalTabs.firstIndex(where: { $0.id == tabId }) else { return }
        let wasSelected = selection == .terminal(tabId)
        terminalTabs.remove(at: closingIndex)

        guard wasSelected else { return }
        selection = fallbackSelection(
            removing: .terminal(tabId),
            editorTabIds: editorTabIds
        )
    }

    func closeEditorTab(_ tabId: UUID, remainingEditorTabIds: [UUID]) {
        guard selection == .editor(tabId) else { return }
        selection = fallbackSelection(
            removing: .editor(tabId),
            editorTabIds: remainingEditorTabIds
        )
    }

    private func fallbackSelection(
        removing removedTab: WorkspaceTabSelection,
        editorTabIds: [UUID]
    ) -> WorkspaceTabSelection {
        let orderedTabs = orderedTabs(editorTabIds: editorTabIds)
        guard let removedIndex = orderedTabs.firstIndex(of: removedTab) else {
            return .conversation
        }

        var remainingTabs = orderedTabs
        remainingTabs.remove(at: removedIndex)

        if removedIndex < remainingTabs.count {
            return remainingTabs[removedIndex]
        }

        return remainingTabs.last ?? .conversation
    }

    private func orderedTabs(editorTabIds: [UUID]) -> [WorkspaceTabSelection] {
        [.conversation]
            + terminalTabs.map { .terminal($0.id) }
            + editorTabIds.map { .editor($0) }
    }
}
