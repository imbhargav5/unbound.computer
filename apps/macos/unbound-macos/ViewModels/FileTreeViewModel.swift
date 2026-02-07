//
//  FileTreeViewModel.swift
//  unbound-macos
//
//  ViewModel for file tree state management.
//  Eliminates deep binding chains by providing single source of truth
//  for expansion state and file selection.
//

import Foundation

// MARK: - File Tree ViewModel

@MainActor
@Observable
class FileTreeViewModel {
    // MARK: - Dependencies

    private let daemonClient: DaemonClient

    // MARK: - File Tree State

    /// Root items of the file tree (all files view)
    private(set) var allFilesTree: [FileItem] = []

    /// Root items for changes view (git changes only)
    private(set) var changesTree: [FileItem] = []

    /// Set of expanded folder paths (single source of truth)
    private(set) var expandedPaths: Set<String> = []

    /// Currently selected file path
    var selectedFilePath: String?

    /// Loading state
    private(set) var isLoading = false

    /// Root loaded state
    private(set) var isRootLoaded = false

    /// Active session ID for file browsing
    private var sessionId: UUID?

    /// Count of files with changes (for badge display)
    var changesCount: Int {
        countFiles(in: changesTree)
    }

    private func countFiles(in items: [FileItem]) -> Int {
        items.reduce(0) { count, item in
            if item.type == .file {
                return count + 1
            } else {
                return count + countFiles(in: item.children)
            }
        }
    }

    // MARK: - Indexed Lookup

    /// Index for O(1) item lookup by path
    private var allFilesByPath: [String: FileItem] = [:]
    private var changesByPath: [String: FileItem] = [:]

    // MARK: - Initialization

    init(daemonClient: DaemonClient = .shared) {
        self.daemonClient = daemonClient
    }

    // MARK: - Session Management

    func setSessionId(_ id: UUID?) {
        guard sessionId != id else { return }
        sessionId = id
        clearFileTree()
    }

    // MARK: - Loading

    /// Load the root file tree for the current session
    func loadRoot() async {
        guard !isLoading, !isRootLoaded, let sessionId else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let entries = try await daemonClient.listRepositoryFiles(
                sessionId: sessionId.uuidString.lowercased(),
                relativePath: ""
            )
            let items = entries.map { makeFileItem(from: $0) }
            allFilesTree = items
            allFilesByPath = buildIndex(from: items)
            isRootLoaded = true
        } catch {
            allFilesTree = []
            allFilesByPath = [:]
        }
    }

    /// Load children for a specific folder path
    func loadChildren(for path: String) async {
        guard let sessionId else { return }

        if let existing = allFilesByPath[path], existing.childrenLoaded {
            return
        }

        do {
            let entries = try await daemonClient.listRepositoryFiles(
                sessionId: sessionId.uuidString.lowercased(),
                relativePath: path
            )
            let children = entries.map { makeFileItem(from: $0) }

            var didUpdate = false
            updateItem(&allFilesTree, path: path) { item in
                item.children = children
                item.childrenLoaded = true
                item.hasChildrenHint = !children.isEmpty
            } didUpdate: {
                didUpdate = true
            }

            if didUpdate {
                allFilesByPath = buildIndex(from: allFilesTree)
            }
        } catch {
            // Keep previous state on error
        }
    }

    /// Clear the file tree
    func clearFileTree() {
        allFilesTree = []
        changesTree = []
        allFilesByPath = [:]
        changesByPath = [:]
        expandedPaths = []
        selectedFilePath = nil
        isRootLoaded = false
    }

    // MARK: - Expansion State

    /// Toggle expansion state for a folder
    func toggleExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    /// Check if an item is expanded
    func isExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }

    /// Expand a specific folder
    func expand(_ path: String) {
        expandedPaths.insert(path)
    }

    /// Collapse a specific folder
    func collapse(_ path: String) {
        expandedPaths.remove(path)
    }

    /// Expand all folders
    func expandAll() {
        func collectFolderPaths(from items: [FileItem]) -> Set<String> {
            var paths = Set<String>()
            for item in items where item.isDirectory {
                paths.insert(item.path)
                paths.formUnion(collectFolderPaths(from: item.children))
            }
            return paths
        }

        expandedPaths = collectFolderPaths(from: allFilesTree)
            .union(collectFolderPaths(from: changesTree))
    }

    /// Collapse all folders
    func collapseAll() {
        expandedPaths.removeAll()
    }

    // MARK: - Item Lookup

    /// Get item by path from all files
    func allFilesItem(for path: String) -> FileItem? {
        allFilesByPath[path]
    }

    /// Get item by path from changes
    func changesItem(for path: String) -> FileItem? {
        changesByPath[path]
    }

    /// Get the currently selected file item
    var selectedFileItem: FileItem? {
        guard let path = selectedFilePath else { return nil }
        return allFilesByPath[path] ?? changesByPath[path]
    }

    // MARK: - Selection

    /// Select a file by path
    func selectFile(_ path: String) {
        selectedFilePath = path
    }

    /// Clear selection
    func clearSelection() {
        selectedFilePath = nil
    }

    // MARK: - Private Helpers

    private func makeFileItem(from entry: DaemonFileEntry) -> FileItem {
        let type: FileItemType = entry.isDir ? .folder : FileItemType.fromExtension((entry.name as NSString).pathExtension)
        return FileItem(
            path: entry.path,
            name: entry.name,
            type: type,
            children: [],
            isExpanded: false,
            gitStatus: .unchanged,
            isDirectory: entry.isDir,
            childrenLoaded: !entry.isDir,
            hasChildrenHint: entry.hasChildren
        )
    }

    /// Build an index from a tree of FileItems for O(1) lookup
    private func buildIndex(from items: [FileItem]) -> [String: FileItem] {
        var index: [String: FileItem] = [:]

        func indexItems(_ items: [FileItem]) {
            for item in items {
                index[item.path] = item
                if item.hasChildren {
                    indexItems(item.children)
                }
            }
        }

        indexItems(items)
        return index
    }

    private func updateItem(
        _ items: inout [FileItem],
        path: String,
        update: (inout FileItem) -> Void,
        didUpdate: () -> Void
    ) {
        for index in items.indices {
            if items[index].path == path {
                update(&items[index])
                didUpdate()
                return
            }
            if !items[index].children.isEmpty {
                updateItem(&items[index].children, path: path, update: update, didUpdate: didUpdate)
            }
        }
    }

    // MARK: - Preview Support

    #if DEBUG
    /// Configure this view model with fake data for Xcode Canvas previews.
    /// Bypasses daemon file listing entirely by setting state directly.
    func configureForPreview(
        fileTree: [FileItem] = [],
        expandedPaths: Set<String> = [],
        selectedFilePath: String? = nil
    ) {
        self.allFilesTree = fileTree
        self.expandedPaths = expandedPaths
        self.isRootLoaded = true
        self.selectedFilePath = selectedFilePath
        self.allFilesByPath = buildIndex(from: fileTree)
    }
    #endif
}
