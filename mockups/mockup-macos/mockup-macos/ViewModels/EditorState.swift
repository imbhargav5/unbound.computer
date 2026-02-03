//
//  EditorState.swift
//  mockup-macos
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

    init(tabs: [EditorTab] = FakeData.editorFileSeeds.map { seed in
        EditorTab(kind: .file, path: seed.path, content: seed.content, language: seed.language)
    }) {
        self.tabs = tabs
        self.selectedTabId = tabs.first?.id
    }

    func openFileTab(relativePath: String, fullPath: String? = nil) {
        _ = fullPath
        if let existing = tabs.first(where: { $0.kind == .file && $0.path == relativePath }) {
            selectedTabId = existing.id
            return
        }

        if let seed = FakeData.editorFileSeed(for: relativePath) {
            let tab = EditorTab(kind: .file, path: seed.path, content: seed.content, language: seed.language)
            tabs.append(tab)
            selectedTabId = tab.id
        } else {
            let placeholder = EditorTab(
                kind: .file,
                path: relativePath,
                content: "// Preview unavailable for \(relativePath)",
                language: nil
            )
            tabs.append(placeholder)
            selectedTabId = placeholder.id
        }
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
            var state = DiffLoadState()
            state.diff = FakeData.fileDiffsByPath[relativePath]
            diffStates[relativePath] = state
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
}
