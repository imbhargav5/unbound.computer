//! Data types for git operations.
//!
//! These types are designed for serialization over IPC and match the
//! corresponding Swift types in the macOS application.

use serde::{Deserialize, Serialize};

/// File status in git.
///
/// Represents the state of a file relative to the index or working tree.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GitFileStatus {
    /// File has been modified.
    Modified,
    /// File has been added (new file).
    Added,
    /// File has been deleted.
    Deleted,
    /// File has been renamed.
    Renamed,
    /// File has been copied.
    Copied,
    /// File is not tracked by git.
    Untracked,
    /// File is ignored by .gitignore.
    Ignored,
    /// File type has changed (e.g., file to symlink).
    Typechange,
    /// File cannot be read.
    Unreadable,
    /// File has merge conflicts.
    Conflicted,
    /// File is unchanged.
    Unchanged,
}

impl GitFileStatus {
    /// Convert from git2 Delta (test utility).
    #[cfg(test)]
    pub(crate) fn from_delta(delta: git2::Delta) -> Self {
        match delta {
            git2::Delta::Added => GitFileStatus::Added,
            git2::Delta::Deleted => GitFileStatus::Deleted,
            git2::Delta::Modified => GitFileStatus::Modified,
            git2::Delta::Renamed => GitFileStatus::Renamed,
            git2::Delta::Copied => GitFileStatus::Copied,
            git2::Delta::Ignored => GitFileStatus::Ignored,
            git2::Delta::Untracked => GitFileStatus::Untracked,
            git2::Delta::Typechange => GitFileStatus::Typechange,
            git2::Delta::Unreadable => GitFileStatus::Unreadable,
            git2::Delta::Conflicted => GitFileStatus::Conflicted,
            git2::Delta::Unmodified => GitFileStatus::Unchanged,
        }
    }
}

/// A file entry in git status.
///
/// Represents a single file that has changes relative to the index
/// or working tree.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatusFile {
    /// File path relative to repository root.
    pub path: String,
    /// Status of the file.
    pub status: GitFileStatus,
    /// Whether the file is staged (in the index).
    ///
    /// - `true`: Changes are staged and will be included in the next commit.
    /// - `false`: Changes are in the working tree only.
    pub staged: bool,
}

/// Result of git status operation.
///
/// Contains the complete status of a repository including all changed
/// files, the current branch, and whether the working directory is clean.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatusResult {
    /// List of files with their statuses.
    ///
    /// Only includes files with changes; unchanged files are omitted.
    pub files: Vec<GitStatusFile>,
    /// Current branch name.
    ///
    /// `None` if in a detached HEAD state.
    pub branch: Option<String>,
    /// Whether the working directory is clean.
    ///
    /// `true` if there are no staged or unstaged changes.
    pub is_clean: bool,
}

/// Result of git diff operation for a single file.
///
/// Contains the unified diff output and metadata about the changes.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitDiffResult {
    /// File path relative to repository root.
    pub file_path: String,
    /// Diff content in unified format.
    ///
    /// Contains the full diff output with headers, hunks, and
    /// context lines. For binary files, this will be "(Binary file)".
    pub diff: String,
    /// Whether the file is binary.
    ///
    /// Binary files cannot be meaningfully diffed as text.
    pub is_binary: bool,
    /// Whether the diff was truncated.
    ///
    /// Large diffs may be truncated to prevent excessive memory usage.
    pub is_truncated: bool,
    /// Number of added lines.
    pub additions: u32,
    /// Number of deleted lines.
    pub deletions: u32,
}

/// A git commit entry for history display.
///
/// Contains all metadata about a commit for display in the UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommit {
    /// Full SHA hash (40 characters).
    pub oid: String,
    /// Short SHA hash (7 characters).
    ///
    /// Suitable for display in space-constrained contexts.
    pub short_oid: String,
    /// Full commit message including body.
    pub message: String,
    /// First line of commit message.
    ///
    /// The summary/title of the commit.
    pub summary: String,
    /// Author name.
    pub author_name: String,
    /// Author email.
    pub author_email: String,
    /// Author timestamp (Unix seconds since epoch).
    pub author_time: i64,
    /// Committer name.
    ///
    /// May differ from author for rebased/cherry-picked commits.
    pub committer_name: String,
    /// Committer timestamp (Unix seconds since epoch).
    pub committer_time: i64,
    /// Parent commit OIDs.
    ///
    /// Used for graph visualization. Merge commits have multiple parents.
    pub parent_oids: Vec<String>,
}

/// A git branch entry.
///
/// Contains information about a single branch including tracking status.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBranch {
    /// Branch name (without refs/heads/ prefix).
    pub name: String,
    /// Whether this is the currently checked out branch.
    pub is_current: bool,
    /// Whether this is a remote-tracking branch.
    ///
    /// Remote branches have names like "origin/main".
    pub is_remote: bool,
    /// Upstream branch name if tracking is configured.
    ///
    /// For local branches, this is the remote branch being tracked.
    pub upstream: Option<String>,
    /// Number of commits ahead of upstream.
    ///
    /// Commits on this branch not yet pushed to upstream.
    pub ahead: u32,
    /// Number of commits behind upstream.
    ///
    /// Commits on upstream not yet pulled to this branch.
    pub behind: u32,
    /// OID of the branch's HEAD commit.
    pub head_oid: String,
}

/// Result of git log operation.
///
/// Contains paginated commit history for display.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitLogResult {
    /// List of commits in reverse chronological order.
    pub commits: Vec<GitCommit>,
    /// Whether there are more commits beyond the limit.
    ///
    /// Used for implementing pagination / infinite scroll.
    pub has_more: bool,
    /// Total count if available (may be expensive to compute).
    ///
    /// This is typically `None` as counting all commits is expensive.
    pub total_count: Option<u32>,
}

/// Result of git branches operation.
///
/// Contains all branches in the repository organized by type.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBranchesResult {
    /// List of local branches.
    ///
    /// Sorted with current branch first, then alphabetically.
    pub local: Vec<GitBranch>,
    /// List of remote-tracking branches.
    ///
    /// Sorted alphabetically.
    pub remote: Vec<GitBranch>,
    /// Current branch name.
    ///
    /// `None` if in a detached HEAD state.
    pub current: Option<String>,
}
