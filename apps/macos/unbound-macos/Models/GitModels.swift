//
//  GitModels.swift
//  unbound-macos
//
//  Git data models for commit history, branches, and staging operations.
//  Matches daemon-config-and-utils/src/git.rs types.
//

import Foundation
import SwiftUI

// MARK: - Git Commit

/// A git commit entry for history display.
struct GitCommit: Codable, Identifiable, Hashable {
    /// Full SHA hash.
    let oid: String
    /// Short SHA hash (7 characters).
    let shortOid: String
    /// Full commit message.
    let message: String
    /// First line of commit message.
    let summary: String
    /// Author name.
    let authorName: String
    /// Author email.
    let authorEmail: String
    /// Author timestamp (Unix seconds).
    let authorTime: Int64
    /// Committer name.
    let committerName: String
    /// Committer timestamp (Unix seconds).
    let committerTime: Int64
    /// Parent commit OIDs (for graph visualization).
    let parentOids: [String]

    var id: String { oid }

    enum CodingKeys: String, CodingKey {
        case oid
        case shortOid = "short_oid"
        case message
        case summary
        case authorName = "author_name"
        case authorEmail = "author_email"
        case authorTime = "author_time"
        case committerName = "committer_name"
        case committerTime = "committer_time"
        case parentOids = "parent_oids"
    }

    /// Author date as Swift Date.
    var authorDate: Date {
        Date(timeIntervalSince1970: TimeInterval(authorTime))
    }

    /// Committer date as Swift Date.
    var committerDate: Date {
        Date(timeIntervalSince1970: TimeInterval(committerTime))
    }

    /// Formatted relative time (e.g., "2 hours ago").
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: authorDate, relativeTo: Date())
    }

    /// Author initials for avatar.
    var authorInitials: String {
        let parts = authorName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(authorName.prefix(2)).uppercased()
    }

    /// Is this a merge commit?
    var isMergeCommit: Bool {
        parentOids.count > 1
    }
}

// MARK: - Git Branch

/// A git branch entry.
struct GitBranch: Codable, Identifiable, Hashable {
    /// Branch name (without refs/heads/ prefix).
    let name: String
    /// Whether this is the currently checked out branch.
    let isCurrent: Bool
    /// Whether this is a remote-tracking branch.
    let isRemote: Bool
    /// Upstream branch name if set.
    let upstream: String?
    /// Number of commits ahead of upstream.
    let ahead: UInt32
    /// Number of commits behind upstream.
    let behind: UInt32
    /// OID of the branch's HEAD commit.
    let headOid: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case isCurrent = "is_current"
        case isRemote = "is_remote"
        case upstream
        case ahead
        case behind
        case headOid = "head_oid"
    }

    /// Display name (strips origin/ for remote branches).
    var displayName: String {
        if isRemote, name.hasPrefix("origin/") {
            return String(name.dropFirst(7))
        }
        return name
    }

    /// Upstream status string (e.g., "+2 -1").
    var upstreamStatus: String? {
        guard upstream != nil else { return nil }
        if ahead == 0 && behind == 0 {
            return nil
        }
        var parts: [String] = []
        if ahead > 0 { parts.append("+\(ahead)") }
        if behind > 0 { parts.append("-\(behind)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Git Log Result

/// Result of git log operation.
struct GitLogResult: Codable {
    /// List of commits.
    let commits: [GitCommit]
    /// Whether there are more commits beyond the limit.
    let hasMore: Bool
    /// Total count if available (may be expensive to compute).
    let totalCount: UInt32?

    enum CodingKeys: String, CodingKey {
        case commits
        case hasMore = "has_more"
        case totalCount = "total_count"
    }
}

// MARK: - Git Branches Result

/// Result of git branches operation.
struct GitBranchesResult: Codable {
    /// List of local branches.
    let local: [GitBranch]
    /// List of remote-tracking branches.
    let remote: [GitBranch]
    /// Current branch name.
    let current: String?
}

// MARK: - Git Status File (extended)

/// Extended file status for the Changes tab.
struct GitStatusFile: Codable, Identifiable, Hashable {
    /// File path relative to repository root.
    let path: String
    /// Status of the file.
    let status: GitFileStatusType
    /// Whether the file is staged.
    let staged: Bool
    /// Number of lines added (optional, from git diff --numstat).
    var additions: Int?
    /// Number of lines deleted (optional, from git diff --numstat).
    var deletions: Int?

    var id: String { path }

    /// File name only (without directory).
    var fileName: String {
        (path as NSString).lastPathComponent
    }

    /// Directory path (without file name).
    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
}

/// Git file status type.
enum GitFileStatusType: String, Codable, Hashable {
    case modified
    case added
    case deleted
    case renamed
    case copied
    case untracked
    case ignored
    case typechange
    case unreadable
    case conflicted
    case unchanged

    var displayName: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .untracked: return "Untracked"
        case .ignored: return "Ignored"
        case .typechange: return "Type Changed"
        case .unreadable: return "Unreadable"
        case .conflicted: return "Conflicted"
        case .unchanged: return "Unchanged"
        }
    }

    /// Git-standard single-character indicator (matches `git status --short`)
    var indicator: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "U"
        case .ignored: return "!"
        case .typechange: return "T"
        case .unreadable: return "X"
        case .conflicted: return "U"
        case .unchanged: return " "
        }
    }

    /// Semantic color aligned to the app palette.
    func color(_ colors: ThemeColors) -> Color {
        switch self {
        case .modified: return colors.fileModified
        case .added: return colors.diffAddition
        case .deleted: return colors.diffDeletion
        case .renamed: return colors.accentAmber
        case .copied: return colors.accentAmber
        case .untracked: return colors.fileUntracked
        case .ignored: return colors.textInactive
        case .typechange: return colors.accentAmber
        case .unreadable: return colors.destructive
        case .conflicted: return colors.destructive
        case .unchanged: return .clear
        }
    }

    /// SF Symbol icon name - uses semantic Git metaphors
    /// Avoids abstract icons like pencil; prefers explicit status symbols
    var iconName: String {
        switch self {
        case .modified: return "circle.fill"              // Filled dot for modified
        case .added: return "plus"                        // Standard Git + for added
        case .deleted: return "minus"                     // Standard Git - for deleted
        case .renamed: return "arrow.right"               // Movement indicator
        case .copied: return "doc.on.doc"                 // Duplicate indicator
        case .untracked: return "questionmark"            // Unknown/untracked
        case .ignored: return "eye.slash"                 // Hidden/ignored
        case .typechange: return "arrow.triangle.swap"    // Type swap
        case .unreadable: return "exclamationmark.triangle.fill" // Error
        case .conflicted: return "exclamationmark.2"      // Conflict
        case .unchanged: return ""
        }
    }

    /// Compact badge text for inline display (matches VS Code style)
    var badge: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "U"
        case .ignored: return "I"
        case .typechange: return "T"
        case .unreadable: return "!"
        case .conflicted: return "!"
        case .unchanged: return ""
        }
    }
}

// MARK: - Git Status Result (extended)

/// Result of git status operation with staged/unstaged separation.
struct GitStatusResult: Codable {
    /// List of files with their statuses.
    let files: [GitStatusFile]
    /// Current branch name.
    let branch: String?
    /// Whether the working directory is clean.
    let isClean: Bool

    enum CodingKeys: String, CodingKey {
        case files
        case branch
        case isClean = "is_clean"
    }

    /// Staged files only.
    var stagedFiles: [GitStatusFile] {
        files.filter { $0.staged }
    }

    /// Unstaged files only.
    var unstagedFiles: [GitStatusFile] {
        files.filter { !$0.staged && $0.status != .untracked }
    }

    /// Untracked files only.
    var untrackedFiles: [GitStatusFile] {
        files.filter { $0.status == .untracked }
    }
}

// MARK: - GitHub CLI Models

/// Authentication host entry returned by `gh.auth_status`.
struct GHAuthHost: Codable, Hashable, Identifiable {
    let host: String
    let login: String?
    let state: String
    let active: Bool
    let tokenSource: String?
    let gitProtocol: String?
    let error: String?

    var id: String { "\(host):\(login ?? "unknown")" }

    enum CodingKeys: String, CodingKey {
        case host
        case login
        case state
        case active
        case tokenSource = "token_source"
        case gitProtocol = "git_protocol"
        case error
    }
}

/// Result payload for `gh.auth_status`.
struct GHAuthStatusResult: Codable {
    let hosts: [GHAuthHost]
    let authenticatedHostCount: Int

    enum CodingKeys: String, CodingKey {
        case hosts
        case authenticatedHostCount = "authenticated_host_count"
    }
}

struct GHPullRequestAuthor: Codable, Hashable {
    let login: String
}

struct GHPullRequestLabel: Codable, Hashable, Identifiable {
    let name: String
    var id: String { name }
}

/// Normalized PR detail returned across create/view/list/merge flows.
struct GHPullRequest: Codable, Identifiable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool
    let baseRefName: String?
    let headRefName: String?
    let mergeStateStatus: String?
    let mergeable: String?
    let reviewDecision: String?
    let author: GHPullRequestAuthor?
    let labels: [GHPullRequestLabel]
    let body: String?
    let createdAt: String?
    let updatedAt: String?
    let statusCheckRollup: AnyCodableValue?

    var id: Int { number }

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case url
        case state
        case isDraft = "is_draft"
        case baseRefName = "base_ref_name"
        case headRefName = "head_ref_name"
        case mergeStateStatus = "merge_state_status"
        case mergeable
        case reviewDecision = "review_decision"
        case author
        case labels
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case statusCheckRollup = "status_check_rollup"
    }
}

struct GHPRCreateResponse: Codable {
    let url: String
    let pullRequest: GHPullRequest

    enum CodingKeys: String, CodingKey {
        case url
        case pullRequest = "pull_request"
    }
}

struct GHPRViewResponse: Codable {
    let pullRequest: GHPullRequest

    enum CodingKeys: String, CodingKey {
        case pullRequest = "pull_request"
    }
}

struct GHPRListResponse: Codable {
    let pullRequests: [GHPullRequest]
    let count: Int

    enum CodingKeys: String, CodingKey {
        case pullRequests = "pull_requests"
        case count
    }
}

struct GHPRCheckItem: Codable, Hashable, Identifiable {
    let name: String
    let state: String?
    let bucket: String?
    let workflow: String?
    let description: String?
    let event: String?
    let link: String?
    let startedAt: String?
    let completedAt: String?

    var id: String { "\(name):\(workflow ?? "none")" }

    enum CodingKeys: String, CodingKey {
        case name
        case state
        case bucket
        case workflow
        case description
        case event
        case link
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct GHPRChecksSummary: Codable, Hashable {
    let total: Int
    let passing: Int
    let failing: Int
    let pending: Int
    let skipped: Int
    let cancelled: Int
}

struct GHPRChecksResponse: Codable {
    let checks: [GHPRCheckItem]
    let summary: GHPRChecksSummary
}

enum GHPRMergeMethod: String, Codable, CaseIterable {
    case merge
    case squash
    case rebase
}

struct GHPRMergeResponse: Codable {
    let merged: Bool
    let mergeMethod: GHPRMergeMethod
    let deletedBranch: Bool
    let pullRequest: GHPullRequest

    enum CodingKeys: String, CodingKey {
        case merged
        case mergeMethod = "merge_method"
        case deletedBranch = "deleted_branch"
        case pullRequest = "pull_request"
    }
}

enum GHPRListState: String, Codable, CaseIterable {
    case open
    case closed
    case merged
    case all
}

// MARK: - Commit Graph

/// Represents a node in the commit graph for visualization.
struct CommitGraphNode: Identifiable {
    let commit: GitCommit
    /// Column position in the graph (0 = leftmost).
    let column: Int
    /// Lines to draw from this node to parents.
    let parentConnections: [ParentConnection]
    /// Whether this node starts a new branch line.
    let startsNewLine: Bool

    var id: String { commit.oid }

    struct ParentConnection {
        let parentOid: String
        let fromColumn: Int
        let toColumn: Int
        let isMerge: Bool
    }
}

// MARK: - Right Sidebar Tab

/// Tabs for the right sidebar panel.
enum RightSidebarTab: String, CaseIterable, Identifiable {
    case spec = "Spec"
    case changes = "Changes"
    case files = "Files"
    case commits = "Commits"
    case pullRequests = "PRs"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .spec: return "doc.text"
        case .changes: return "arrow.triangle.branch"
        case .files: return "folder"
        case .commits: return "clock.arrow.circlepath"
        case .pullRequests: return "arrow.triangle.pull"
        }
    }
}
