//
//  EditorState.swift
//  unbound-macos
//
//  View model for editor tabs and diff loading state.
//

import Foundation

@MainActor
@Observable
class EditorState {
    var tabs: [EditorTab]
    var selectedTabId: UUID?
    var diffStates: [String: DiffLoadState] = [:]

    init(tabs: [EditorTab] = []) {
        self.tabs = tabs
        self.selectedTabId = tabs.first?.id
    }

    func openFileTab(relativePath: String, fullPath: String) {
        if let existing = tabs.first(where: { $0.kind == .file && $0.path == relativePath }) {
            selectedTabId = existing.id
            return
        }

        let tab = EditorTab(kind: .file, path: relativePath, fullPath: fullPath)
        tabs.append(tab)
        selectedTabId = tab.id
    }

    func openDiffTab(relativePath: String) {
        if let existing = tabs.first(where: { $0.kind == .diff && $0.path == relativePath }) {
            selectedTabId = existing.id
            return
        }

        let tab = EditorTab(kind: .diff, path: relativePath)
        tabs.append(tab)
        selectedTabId = tab.id

        if diffStates[relativePath] == nil {
            diffStates[relativePath] = DiffLoadState()
        }
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        if selectedTabId == id {
            if tabs.count > 1 {
                let nextIndex = index < tabs.count - 1 ? index + 1 : index - 1
                selectedTabId = tabs[nextIndex].id
            } else {
                selectedTabId = nil
            }
        }

        tabs.removeAll { $0.id == id }
    }

    func selectTab(id: UUID) {
        selectedTabId = id
    }

    func setDiffLoading(for path: String, isLoading: Bool) {
        var state = diffStates[path] ?? DiffLoadState()
        state.isLoading = isLoading
        diffStates[path] = state
    }

    func setDiff(for path: String, diff: FileDiff?) {
        var state = diffStates[path] ?? DiffLoadState()
        state.diff = diff
        state.errorMessage = nil
        diffStates[path] = state
    }

    func setDiffError(for path: String, message: String) {
        var state = diffStates[path] ?? DiffLoadState()
        state.errorMessage = message
        state.diff = nil
        state.isLoading = false
        diffStates[path] = state
    }
}
