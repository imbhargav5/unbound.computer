//
//  GitViewModel.swift
//  unbound-macos
//
//  ViewModel for git state management in the right sidebar.
//  Manages commits, branches, and staging operations.
//

import Foundation
import Logging

private let logger = Logger(label: "app.ui.git")

// MARK: - Git ViewModel

@Observable
class GitViewModel {
    // MARK: - Dependencies

    private weak var daemonClient: DaemonClient?

    // MARK: - Repository State

    /// Current repository path
    private(set) var repositoryPath: String?

    /// Current branch name
    private(set) var currentBranch: String?

    // MARK: - Status State

    /// Git status result (files with changes)
    private(set) var status: GitStatusResult?

    /// Staged files
    var stagedFiles: [GitStatusFile] {
        status?.stagedFiles ?? []
    }

    /// Unstaged files (modified, not untracked)
    var unstagedFiles: [GitStatusFile] {
        status?.unstagedFiles ?? []
    }

    /// Untracked files
    var untrackedFiles: [GitStatusFile] {
        status?.untrackedFiles ?? []
    }

    /// Total count of changed files
    var changesCount: Int {
        status?.files.count ?? 0
    }

    /// Is working directory clean?
    var isClean: Bool {
        status?.isClean ?? true
    }

    // MARK: - Commits State

    /// Commit history
    private(set) var commits: [GitCommit] = []

    /// Whether there are more commits to load
    private(set) var hasMoreCommits: Bool = false

    /// Computed graph nodes for visualization
    private(set) var commitGraph: [CommitGraphNode] = []

    // MARK: - Branches State

    /// Local branches
    private(set) var localBranches: [GitBranch] = []

    /// Remote branches
    private(set) var remoteBranches: [GitBranch] = []

    /// Selected branch for viewing history
    var selectedBranch: String?

    // MARK: - Selection State

    /// Selected file for diff viewing
    var selectedFilePath: String?

    /// Selected commit for details
    var selectedCommitOid: String?

    // MARK: - Loading States

    private(set) var isLoadingStatus: Bool = false
    private(set) var isLoadingCommits: Bool = false
    private(set) var isLoadingBranches: Bool = false
    private(set) var isPerformingAction: Bool = false

    // MARK: - Error State

    private(set) var lastError: String?

    // MARK: - Initialization

    init(daemonClient: DaemonClient? = nil) {
        self.daemonClient = daemonClient
    }

    func setDaemonClient(_ client: DaemonClient) {
        self.daemonClient = client
    }

    // MARK: - Repository

    /// Set the current repository path and refresh all data
    func setRepository(path: String?) async {
        repositoryPath = path

        if path != nil {
            await refreshAll()
        } else {
            clearAll()
        }
    }

    /// Clear all state
    func clearAll() {
        status = nil
        commits = []
        commitGraph = []
        localBranches = []
        remoteBranches = []
        currentBranch = nil
        selectedBranch = nil
        selectedFilePath = nil
        selectedCommitOid = nil
        lastError = nil
    }

    /// Refresh all git data
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshStatus() }
            group.addTask { await self.refreshBranches() }
            group.addTask { await self.refreshCommits() }
        }
    }

    // MARK: - Status Operations

    /// Refresh git status
    func refreshStatus() async {
        guard let path = repositoryPath, let client = daemonClient else { return }

        isLoadingStatus = true
        defer { isLoadingStatus = false }

        do {
            status = try await client.getGitStatusV2(path: path)
            currentBranch = status?.branch
            lastError = nil
            logger.debug("Refreshed git status: \(status?.files.count ?? 0) changed files")
        } catch {
            logger.warning("Failed to get git status: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Stage specific files
    func stageFiles(_ paths: [String]) async {
        guard let repoPath = repositoryPath, let client = daemonClient else { return }
        guard !paths.isEmpty else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await client.stageFiles(path: repoPath, files: paths)
            await refreshStatus()
            logger.info("Staged \(paths.count) files")
        } catch {
            logger.error("Failed to stage files: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Stage all files
    func stageAll() async {
        let allPaths = (unstagedFiles + untrackedFiles).map { $0.path }
        await stageFiles(allPaths)
    }

    /// Unstage specific files
    func unstageFiles(_ paths: [String]) async {
        guard let repoPath = repositoryPath, let client = daemonClient else { return }
        guard !paths.isEmpty else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await client.unstageFiles(path: repoPath, files: paths)
            await refreshStatus()
            logger.info("Unstaged \(paths.count) files")
        } catch {
            logger.error("Failed to unstage files: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Unstage all files
    func unstageAll() async {
        let allPaths = stagedFiles.map { $0.path }
        await unstageFiles(allPaths)
    }

    /// Discard changes in specific files
    func discardChanges(_ paths: [String]) async {
        guard let repoPath = repositoryPath, let client = daemonClient else { return }
        guard !paths.isEmpty else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await client.discardChanges(path: repoPath, files: paths)
            await refreshStatus()
            logger.info("Discarded changes in \(paths.count) files")
        } catch {
            logger.error("Failed to discard changes: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - Commits Operations

    /// Refresh commit history
    func refreshCommits(limit: Int = 50) async {
        guard let path = repositoryPath, let client = daemonClient else { return }

        isLoadingCommits = true
        defer { isLoadingCommits = false }

        do {
            let result = try await client.getGitLog(
                path: path,
                limit: limit,
                branch: selectedBranch
            )
            commits = result.commits
            hasMoreCommits = result.hasMore
            commitGraph = computeCommitGraph(commits)
            lastError = nil
            logger.debug("Loaded \(commits.count) commits")
        } catch {
            logger.warning("Failed to get commit history: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Load more commits (pagination)
    func loadMoreCommits() async {
        guard hasMoreCommits else { return }
        guard let path = repositoryPath, let client = daemonClient else { return }

        isLoadingCommits = true
        defer { isLoadingCommits = false }

        do {
            let result = try await client.getGitLog(
                path: path,
                limit: 50,
                offset: commits.count,
                branch: selectedBranch
            )
            commits.append(contentsOf: result.commits)
            hasMoreCommits = result.hasMore
            commitGraph = computeCommitGraph(commits)
            logger.debug("Loaded \(result.commits.count) more commits, total: \(commits.count)")
        } catch {
            logger.warning("Failed to load more commits: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - Branches Operations

    /// Refresh branches list
    func refreshBranches() async {
        guard let path = repositoryPath, let client = daemonClient else { return }

        isLoadingBranches = true
        defer { isLoadingBranches = false }

        do {
            let result = try await client.getGitBranches(path: path)
            localBranches = result.local
            remoteBranches = result.remote
            if currentBranch == nil {
                currentBranch = result.current
            }
            lastError = nil
            logger.debug("Loaded \(localBranches.count) local, \(remoteBranches.count) remote branches")
        } catch {
            logger.warning("Failed to get branches: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Switch to viewing history for a different branch
    func selectBranch(_ branchName: String?) async {
        selectedBranch = branchName
        await refreshCommits()
    }

    // MARK: - Commit Graph Computation

    /// Compute visual graph nodes from commits.
    /// This creates the column positions and connection lines for visualization.
    private func computeCommitGraph(_ commits: [GitCommit]) -> [CommitGraphNode] {
        guard !commits.isEmpty else { return [] }

        var nodes: [CommitGraphNode] = []
        var activeLines: [String] = [] // OIDs of commits that need lines continuing down

        for commit in commits {
            // Find which column this commit belongs to
            let columnIndex: Int
            if let existingIndex = activeLines.firstIndex(of: commit.oid) {
                columnIndex = existingIndex
            } else {
                // New branch line - find first empty slot or append
                if let emptyIndex = activeLines.firstIndex(of: "") {
                    columnIndex = emptyIndex
                    activeLines[emptyIndex] = commit.oid
                } else {
                    columnIndex = activeLines.count
                    activeLines.append(commit.oid)
                }
            }

            // Compute parent connections
            var connections: [CommitGraphNode.ParentConnection] = []
            for (i, parentOid) in commit.parentOids.enumerated() {
                let toColumn: Int
                if let existingCol = activeLines.firstIndex(of: parentOid) {
                    toColumn = existingCol
                } else {
                    // Parent not yet in active lines, will continue in same column
                    toColumn = columnIndex
                }

                connections.append(CommitGraphNode.ParentConnection(
                    parentOid: parentOid,
                    fromColumn: columnIndex,
                    toColumn: toColumn,
                    isMerge: i > 0
                ))
            }

            // Update active lines for next iteration
            // Remove current commit's line
            if columnIndex < activeLines.count {
                activeLines[columnIndex] = ""
            }

            // Add parent lines
            for parentOid in commit.parentOids {
                if !activeLines.contains(parentOid) {
                    if let emptyIndex = activeLines.firstIndex(of: "") {
                        activeLines[emptyIndex] = parentOid
                    } else {
                        activeLines.append(parentOid)
                    }
                }
            }

            // Clean up trailing empty slots
            while activeLines.last == "" {
                activeLines.removeLast()
            }

            let node = CommitGraphNode(
                commit: commit,
                column: columnIndex,
                parentConnections: connections,
                startsNewLine: !commits.prefix(while: { $0.oid != commit.oid }).contains(where: {
                    $0.parentOids.contains(commit.oid)
                })
            )
            nodes.append(node)
        }

        return nodes
    }

    // MARK: - Selection

    /// Select a file to view its diff
    func selectFile(_ path: String?) {
        selectedFilePath = path
    }

    /// Select a commit to view details
    func selectCommit(_ oid: String?) {
        selectedCommitOid = oid
    }

    /// Get the selected commit
    var selectedCommit: GitCommit? {
        guard let oid = selectedCommitOid else { return nil }
        return commits.first { $0.oid == oid }
    }
}
