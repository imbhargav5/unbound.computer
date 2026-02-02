//
//  GitModels.swift
//  unbound-macos
//
//  Git data models for commit history, branches, and staging operations.
//  Matches daemon-core/src/git.rs types.
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
        case .untracked: return "?"
        case .ignored: return "!"
        case .typechange: return "T"
        case .unreadable: return "X"
        case .conflicted: return "U"
        case .unchanged: return " "
        }
    }

    /// Semantic color following Git conventions:
    /// - Green: Added (new files)
    /// - Yellow: Modified (changes to existing files)
    /// - Red: Deleted/Destructive
    /// - Gray: Untracked/Unknown
    /// - Blue: Renamed/Moved
    var color: Color {
        switch self {
        case .modified: return .yellow       // Yellow - warning/attention
        case .added: return .green           // Green - success/new
        case .deleted: return .red           // Red - destructive
        case .renamed: return .blue          // Blue - info/movement
        case .copied: return .cyan           // Cyan - similar to renamed
        case .untracked: return .gray        // Gray - unknown/pending
        case .ignored: return .secondary     // Darker gray - de-emphasized
        case .typechange: return .purple     // Purple - type change
        case .unreadable: return .red        // Red - error
        case .conflicted: return .orange     // Orange - urgent attention
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
    case changes = "Changes"
    case files = "Files"
    case commits = "Commits"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .changes: return "plus.forwardslash.minus"
        case .files: return "folder"
        case .commits: return "clock.arrow.circlepath"
        }
    }
}
