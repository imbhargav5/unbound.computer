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

@MainActor @Observable
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

    // MARK: - Pull Request State

    /// Pull requests for current repository context.
    private(set) var pullRequests: [GHPullRequest] = []

    /// Currently selected pull request.
    var selectedPullRequest: GHPullRequest?

    /// Latest checks payload for selected pull request.
    private(set) var selectedPullRequestChecks: GHPRChecksResponse?

    /// Last known GH auth status.
    private(set) var ghAuthStatus: GHAuthStatusResult?

    /// Draft title/body inputs for PR creation.
    var prTitle: String = ""
    var prBody: String = ""

    /// Selected merge strategy.
    var prMergeMethod: GHPRMergeMethod = .squash

    // MARK: - Loading States

    private(set) var isLoadingStatus: Bool = false
    private(set) var isLoadingCommits: Bool = false
    private(set) var isLoadingBranches: Bool = false
    private(set) var isPerformingAction: Bool = false
    private(set) var isLoadingPullRequests: Bool = false
    private(set) var isLoadingPullRequestChecks: Bool = false
    private(set) var isCreatingPullRequest: Bool = false
    private(set) var isMergingPullRequest: Bool = false

    // MARK: - Commit State

    /// Commit message for the next commit
    var commitMessage: String = ""

    // MARK: - Error State

    var lastError: String?

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
        pullRequests = []
        selectedPullRequest = nil
        selectedPullRequestChecks = nil
        ghAuthStatus = nil
        prTitle = ""
        prBody = ""
        prMergeMethod = .squash
        lastError = nil
    }

    /// Refresh all git data
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshStatus() }
            group.addTask { await self.refreshBranches() }
            group.addTask { await self.refreshCommits() }
            group.addTask { await self.refreshGHAuthStatus() }
            group.addTask { await self.refreshPullRequests() }
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

    // MARK: - Commit & Push Operations

    /// Create a commit from staged changes
    func commit() async {
        guard let repoPath = repositoryPath, let client = daemonClient else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let result = try await client.gitCommit(path: repoPath, message: message)
            commitMessage = ""
            lastError = nil
            await refreshAll()
            logger.info("Created commit: \(result.shortOid) \(result.summary)")
        } catch {
            logger.error("Failed to commit: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Push commits to remote
    func push() async {
        guard let repoPath = repositoryPath, let client = daemonClient else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let result = try await client.gitPush(path: repoPath)
            lastError = nil
            await refreshAll()
            logger.info("Pushed \(result.branch) to \(result.remote)")
        } catch {
            logger.error("Failed to push: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Commit staged changes then push to remote
    func commitAndPush() async {
        await commit()
        guard lastError == nil else { return }
        await push()
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

    // MARK: - GitHub PR Operations

    /// Refresh GH authentication status.
    func refreshGHAuthStatus() async {
        guard daemonClient != nil else { return }
        guard let client = daemonClient else { return }

        do {
            ghAuthStatus = try await client.ghAuthStatus()
            lastError = nil
        } catch {
            logger.warning("Failed to refresh gh auth status: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Refresh pull requests for current repository.
    func refreshPullRequests(state: GHPRListState = .open) async {
        guard let path = repositoryPath, let client = daemonClient else { return }

        isLoadingPullRequests = true
        defer { isLoadingPullRequests = false }

        do {
            let result = try await client.ghListPRs(path: path, state: state, limit: 20)
            pullRequests = result.pullRequests

            if let selected = selectedPullRequest,
               let refreshedSelected = pullRequests.first(where: { $0.number == selected.number }) {
                selectedPullRequest = refreshedSelected
            } else {
                selectedPullRequest = pullRequests.first
            }

            lastError = nil

            if selectedPullRequest != nil {
                await refreshSelectedPullRequestChecks()
            } else {
                selectedPullRequestChecks = nil
            }
        } catch {
            logger.warning("Failed to refresh pull requests: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Select a pull request and refresh checks.
    func selectPullRequest(_ pullRequest: GHPullRequest) async {
        selectedPullRequest = pullRequest
        await refreshSelectedPullRequestChecks()
    }

    /// Refresh selected pull request details.
    func refreshSelectedPullRequest() async {
        guard let path = repositoryPath, let client = daemonClient else { return }
        guard let selected = selectedPullRequest else { return }

        do {
            let refreshed = try await client.ghViewPR(path: path, selector: "\(selected.number)")
            selectedPullRequest = refreshed
            lastError = nil
        } catch {
            logger.warning("Failed to refresh selected pull request: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Refresh checks for selected pull request.
    func refreshSelectedPullRequestChecks() async {
        guard let path = repositoryPath, let client = daemonClient else { return }
        guard let selected = selectedPullRequest else { return }

        isLoadingPullRequestChecks = true
        defer { isLoadingPullRequestChecks = false }

        do {
            selectedPullRequestChecks = try await client.ghPRChecks(
                path: path,
                selector: "\(selected.number)"
            )
            lastError = nil
        } catch {
            logger.warning("Failed to refresh pull request checks: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Create a new pull request using current draft fields.
    func createPullRequest(
        reviewers: [String] = [],
        labels: [String] = []
    ) async {
        guard let path = repositoryPath, let client = daemonClient else { return }
        let title = prTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isCreatingPullRequest = true
        isPerformingAction = true
        defer {
            isCreatingPullRequest = false
            isPerformingAction = false
        }

        do {
            let body = prBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await client.ghCreatePR(
                path: path,
                title: title,
                body: body.isEmpty ? nil : body,
                reviewers: reviewers,
                labels: labels
            )

            selectedPullRequest = result.pullRequest
            prTitle = ""
            prBody = ""
            lastError = nil

            await refreshPullRequests()
        } catch {
            logger.error("Failed to create pull request: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Merge the selected pull request.
    func mergeSelectedPullRequest(deleteBranch: Bool = false) async {
        guard let path = repositoryPath, let client = daemonClient else { return }
        guard let selected = selectedPullRequest else { return }

        isMergingPullRequest = true
        isPerformingAction = true
        defer {
            isMergingPullRequest = false
            isPerformingAction = false
        }

        do {
            _ = try await client.ghMergePR(
                path: path,
                selector: "\(selected.number)",
                mergeMethod: prMergeMethod,
                deleteBranch: deleteBranch
            )

            lastError = nil
            await refreshPullRequests()
            await refreshSelectedPullRequest()
            await refreshSelectedPullRequestChecks()
        } catch {
            logger.error("Failed to merge pull request: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
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

    // MARK: - Preview Support

    #if DEBUG
    /// Configure this view model with fake data for Xcode Canvas previews.
    /// Bypasses the daemon entirely by setting state directly.
    func configureForPreview(
        repositoryPath: String? = nil,
        currentBranch: String? = nil,
        status: GitStatusResult? = nil,
        commits: [GitCommit] = [],
        localBranches: [GitBranch] = [],
        remoteBranches: [GitBranch] = []
    ) {
        self.repositoryPath = repositoryPath
        self.currentBranch = currentBranch
        self.status = status
        self.commits = commits
        self.localBranches = localBranches
        self.remoteBranches = remoteBranches
        self.commitGraph = computeCommitGraph(commits)
        self.hasMoreCommits = commits.count > 5
    }
    #endif
}
