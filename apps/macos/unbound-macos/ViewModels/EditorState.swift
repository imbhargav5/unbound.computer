//
//  EditorState.swift
//  unbound-macos
//
//  View model for editor tabs, file buffers, and diff loading state.
//

import Foundation

@MainActor
@Observable
class EditorState {
    enum SaveOutcome {
        case noChanges
        case saved
        case conflict(currentRevision: DaemonFileRevision?)
    }

    var tabs: [EditorTab]
    var selectedTabId: UUID?
    var diffStates: [String: DiffLoadState] = [:]
    var documentsByTabId: [UUID: EditorDocumentState] = [:]

    init(tabs: [EditorTab] = []) {
        self.tabs = tabs
        self.selectedTabId = tabs.first?.id
    }

    func openFileTab(relativePath: String, fullPath: String, sessionId: UUID?) {
        if let existing = tabs.first(where: { $0.kind == .file && $0.path == relativePath }) {
            selectedTabId = existing.id
            return
        }

        let tab = EditorTab(kind: .file, path: relativePath, fullPath: fullPath, sessionId: sessionId)
        tabs.append(tab)
        documentsByTabId[tab.id] = EditorDocumentState()
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
        documentsByTabId.removeValue(forKey: id)
    }

    func selectTab(id: UUID) {
        selectedTabId = id
    }

    func tab(for id: UUID) -> EditorTab? {
        tabs.first(where: { $0.id == id })
    }

    func selectedFileTab() -> EditorTab? {
        guard let selectedTabId else { return nil }
        guard let tab = tab(for: selectedTabId), tab.kind == .file else { return nil }
        return tab
    }

    func document(for tabId: UUID) -> EditorDocumentState? {
        documentsByTabId[tabId]
    }

    func isDirty(tabId: UUID) -> Bool {
        documentsByTabId[tabId]?.isDirty ?? false
    }

    func canSave(tabId: UUID) -> Bool {
        guard let state = documentsByTabId[tabId] else { return false }
        return !state.isLoading && !state.isSaving && !state.isReadOnly && state.isDirty
    }

    func updateDocumentContent(for tabId: UUID, content: String) {
        var state = documentsByTabId[tabId] ?? EditorDocumentState()
        state.content = content
        state.isDirty = content != state.baseContent
        state.errorMessage = nil
        documentsByTabId[tabId] = state
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

    func ensureFileLoaded(
        tabId: UUID,
        daemonClient: DaemonClient,
        forceReload: Bool = false
    ) async {
        guard let tab = tab(for: tabId), tab.kind == .file else { return }
        guard let sessionId = tab.sessionId?.uuidString.lowercased() else {
            var state = documentsByTabId[tabId] ?? EditorDocumentState()
            state.errorMessage = "Missing session for file load."
            state.isLoading = false
            documentsByTabId[tabId] = state
            return
        }

        var state = documentsByTabId[tabId] ?? EditorDocumentState()
        if state.isLoading {
            return
        }
        if state.hasLoaded && !forceReload {
            return
        }

        state.isLoading = true
        state.errorMessage = nil
        documentsByTabId[tabId] = state

        do {
            let response = try await daemonClient.readRepositoryFile(
                sessionId: sessionId,
                relativePath: tab.path,
                maxBytes: 4 * 1024 * 1024
            )

            var nextState = documentsByTabId[tabId] ?? EditorDocumentState()
            let fallbackReadOnlyReason: String? = response.isTruncated
                ? "File is too large for full editable load and is open read-only."
                : nil
            let readOnlyReason = response.readOnlyReason ?? fallbackReadOnlyReason

            nextState.content = response.content
            nextState.baseContent = response.content
            nextState.revision = response.revision
            nextState.isDirty = false
            nextState.isLoading = false
            nextState.isSaving = false
            nextState.errorMessage = nil
            nextState.isReadOnly = readOnlyReason != nil
            nextState.readOnlyReason = readOnlyReason
            nextState.hasLoaded = true
            documentsByTabId[tabId] = nextState
        } catch {
            var nextState = documentsByTabId[tabId] ?? EditorDocumentState()
            nextState.isLoading = false
            nextState.errorMessage = error.localizedDescription
            documentsByTabId[tabId] = nextState
        }
    }

    func reloadFile(tabId: UUID, daemonClient: DaemonClient) async {
        await ensureFileLoaded(tabId: tabId, daemonClient: daemonClient, forceReload: true)
    }

    func saveFile(
        tabId: UUID,
        daemonClient: DaemonClient,
        forceOverwrite: Bool = false
    ) async throws -> SaveOutcome {
        guard let tab = tab(for: tabId), tab.kind == .file else {
            return .noChanges
        }
        guard let sessionId = tab.sessionId?.uuidString.lowercased() else {
            return .noChanges
        }

        var state = documentsByTabId[tabId] ?? EditorDocumentState()
        if state.isLoading || state.isSaving || state.isReadOnly {
            return .noChanges
        }
        if !state.isDirty && !forceOverwrite {
            return .noChanges
        }

        state.isSaving = true
        state.errorMessage = nil
        documentsByTabId[tabId] = state

        let savePlan = buildSavePlan(baseContent: state.baseContent, content: state.content)

        do {
            let writeResult: DaemonWriteResult
            switch savePlan {
            case .replaceRange(let startLine, let endLineExclusive, let replacement):
                writeResult = try await daemonClient.replaceRepositoryFileRange(
                    sessionId: sessionId,
                    relativePath: tab.path,
                    startLine: startLine,
                    endLineExclusive: endLineExclusive,
                    replacement: replacement,
                    expectedRevision: state.revision,
                    force: forceOverwrite
                )
            case .writeFull:
                writeResult = try await daemonClient.writeRepositoryFile(
                    sessionId: sessionId,
                    relativePath: tab.path,
                    content: state.content,
                    expectedRevision: state.revision,
                    force: forceOverwrite
                )
            }

            var nextState = documentsByTabId[tabId] ?? EditorDocumentState()
            nextState.isSaving = false
            nextState.errorMessage = nil
            nextState.revision = writeResult.revision
            nextState.baseContent = nextState.content
            nextState.isDirty = false
            documentsByTabId[tabId] = nextState
            return .saved
        } catch let daemonError as DaemonError {
            var nextState = documentsByTabId[tabId] ?? EditorDocumentState()
            nextState.isSaving = false
            switch daemonError {
            case .conflict(let currentRevision):
                nextState.errorMessage = "File changed on disk."
                documentsByTabId[tabId] = nextState
                return .conflict(currentRevision: currentRevision)
            default:
                nextState.errorMessage = daemonError.localizedDescription
                documentsByTabId[tabId] = nextState
                throw daemonError
            }
        } catch {
            var nextState = documentsByTabId[tabId] ?? EditorDocumentState()
            nextState.isSaving = false
            nextState.errorMessage = error.localizedDescription
            documentsByTabId[tabId] = nextState
            throw error
        }
    }

    private enum SavePlan {
        case writeFull
        case replaceRange(startLine: Int, endLineExclusive: Int, replacement: String)
    }

    private func buildSavePlan(baseContent: String, content: String) -> SavePlan {
        let baseLines = ropeStyleLines(baseContent)
        let currentLines = ropeStyleLines(content)

        var prefix = 0
        while prefix < baseLines.count && prefix < currentLines.count && baseLines[prefix] == currentLines[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < (baseLines.count - prefix) &&
            suffix < (currentLines.count - prefix) &&
            baseLines[baseLines.count - 1 - suffix] == currentLines[currentLines.count - 1 - suffix] {
            suffix += 1
        }

        let baseChangedCount = max(0, baseLines.count - prefix - suffix)
        let currentChangedCount = max(0, currentLines.count - prefix - suffix)
        let changedLines = max(baseChangedCount, currentChangedCount)
        let totalLines = max(1, baseLines.count)
        let replacementEnd = currentLines.count - suffix
        let replacementSlice = currentLines[prefix..<replacementEnd]
        let replacement = replacementSlice.joined()

        let ratio = Double(changedLines) / Double(totalLines)
        let replacementBytes = replacement.utf8.count
        if ratio <= 0.35 && replacementBytes <= 512 * 1024 {
            return .replaceRange(
                startLine: prefix,
                endLineExclusive: baseLines.count - suffix,
                replacement: replacement
            )
        }
        return .writeFull
    }

    private func ropeStyleLines(_ text: String) -> [String] {
        var lines: [String] = []
        var lineStart = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            text.formIndex(after: &index)
            if character == "\n" {
                lines.append(String(text[lineStart..<index]))
                lineStart = index
            }
        }

        if lineStart < text.endIndex {
            lines.append(String(text[lineStart..<text.endIndex]))
        } else if text.isEmpty || text.hasSuffix("\n") {
            lines.append("")
        }

        return lines
    }

    // MARK: - Preview Support

    #if DEBUG
    /// Configure this editor state with fake tabs and content for Canvas previews.
    func configureForPreview(
        tabs: [EditorTab] = [],
        selectedTabId: UUID? = nil,
        documentContent: String = "",
        baseContent: String = ""
    ) {
        self.tabs = tabs
        self.selectedTabId = selectedTabId ?? tabs.first?.id

        // Set up document state for the first file tab
        for tab in tabs where tab.kind == .file {
            self.documentsByTabId[tab.id] = EditorDocumentState(
                content: documentContent,
                baseContent: baseContent,
                isDirty: documentContent != baseContent && !documentContent.isEmpty,
                hasLoaded: !documentContent.isEmpty
            )
        }
    }
    #endif
}
