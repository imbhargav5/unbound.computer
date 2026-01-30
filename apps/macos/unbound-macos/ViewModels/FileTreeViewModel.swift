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

@Observable
class FileTreeViewModel {
    // MARK: - Dependencies

    private let fileSystemService: FileSystemService

    // MARK: - File Tree State

    /// Root items of the file tree (all files view)
    private(set) var allFilesTree: [FileItem] = []

    /// Root items for changes view (git changes only)
    private(set) var changesTree: [FileItem] = []

    /// Set of expanded folder IDs (single source of truth)
    private(set) var expandedIds: Set<UUID> = []

    /// Currently selected file ID
    var selectedFileId: UUID?

    /// Loading state
    private(set) var isLoading = false

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

    /// Index for O(1) item lookup by ID
    private var allFilesById: [UUID: FileItem] = [:]
    private var changesById: [UUID: FileItem] = [:]

    // MARK: - Initialization

    init(fileSystemService: FileSystemService) {
        self.fileSystemService = fileSystemService
    }

    // MARK: - Loading

    /// Load the file tree for a directory
    func loadFileTree(at path: String) async {
        isLoading = true
        defer { isLoading = false }

        // Load all files
        let items = fileSystemService.scanDirectory(at: path)
        allFilesTree = items
        allFilesById = buildIndex(from: items)

        // TODO: Load changes from daemon git.status
        // For now, skip git status loading
        changesTree = []
        changesById = [:]
    }

    /// Clear the file tree
    func clearFileTree() {
        allFilesTree = []
        changesTree = []
        allFilesById = [:]
        changesById = [:]
        expandedIds = []
        selectedFileId = nil
    }

    // MARK: - Expansion State

    /// Toggle expansion state for a folder
    func toggleExpanded(_ id: UUID) {
        if expandedIds.contains(id) {
            expandedIds.remove(id)
        } else {
            expandedIds.insert(id)
        }
    }

    /// Check if an item is expanded
    func isExpanded(_ id: UUID) -> Bool {
        expandedIds.contains(id)
    }

    /// Expand a specific folder
    func expand(_ id: UUID) {
        expandedIds.insert(id)
    }

    /// Collapse a specific folder
    func collapse(_ id: UUID) {
        expandedIds.remove(id)
    }

    /// Expand all folders
    func expandAll() {
        func collectFolderIds(from items: [FileItem]) -> Set<UUID> {
            var ids = Set<UUID>()
            for item in items {
                if item.hasChildren {
                    ids.insert(item.id)
                    ids.formUnion(collectFolderIds(from: item.children))
                }
            }
            return ids
        }

        expandedIds = collectFolderIds(from: allFilesTree)
            .union(collectFolderIds(from: changesTree))
    }

    /// Collapse all folders
    func collapseAll() {
        expandedIds.removeAll()
    }

    // MARK: - Item Lookup

    /// Get item by ID from all files
    func allFilesItem(for id: UUID) -> FileItem? {
        allFilesById[id]
    }

    /// Get item by ID from changes
    func changesItem(for id: UUID) -> FileItem? {
        changesById[id]
    }

    /// Get the currently selected file item
    var selectedFileItem: FileItem? {
        guard let id = selectedFileId else { return nil }
        return allFilesById[id] ?? changesById[id]
    }

    // MARK: - Selection

    /// Select a file by ID
    func selectFile(_ id: UUID) {
        selectedFileId = id
    }

    /// Clear selection
    func clearSelection() {
        selectedFileId = nil
    }

    // MARK: - Private Helpers

    /// Build an index from a tree of FileItems for O(1) lookup
    private func buildIndex(from items: [FileItem]) -> [UUID: FileItem] {
        var index: [UUID: FileItem] = [:]

        func indexItems(_ items: [FileItem]) {
            for item in items {
                index[item.id] = item
                if item.hasChildren {
                    indexItems(item.children)
                }
            }
        }

        indexItems(items)
        return index
    }
}
