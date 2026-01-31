//! Git operations using libgit2.
//!
//! Provides native git integration for repository status, diff, commit history,
//! branch operations, and worktree management.

use git2::{BranchType, Delta, DiffOptions, Repository, Sort, StatusOptions};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// File status in git.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GitFileStatus {
    Modified,
    Added,
    Deleted,
    Renamed,
    Copied,
    Untracked,
    Ignored,
    Typechange,
    Unreadable,
    Conflicted,
    Unchanged,
}

impl GitFileStatus {
    /// Convert from git2 Delta.
    fn from_delta(delta: Delta) -> Self {
        match delta {
            Delta::Added => GitFileStatus::Added,
            Delta::Deleted => GitFileStatus::Deleted,
            Delta::Modified => GitFileStatus::Modified,
            Delta::Renamed => GitFileStatus::Renamed,
            Delta::Copied => GitFileStatus::Copied,
            Delta::Ignored => GitFileStatus::Ignored,
            Delta::Untracked => GitFileStatus::Untracked,
            Delta::Typechange => GitFileStatus::Typechange,
            Delta::Unreadable => GitFileStatus::Unreadable,
            Delta::Conflicted => GitFileStatus::Conflicted,
            Delta::Unmodified => GitFileStatus::Unchanged,
        }
    }
}

/// A file entry in git status.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatusFile {
    /// File path relative to repository root.
    pub path: String,
    /// Status of the file.
    pub status: GitFileStatus,
    /// Whether the file is staged.
    pub staged: bool,
}

/// Result of git status operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitStatusResult {
    /// List of files with their statuses.
    pub files: Vec<GitStatusFile>,
    /// Current branch name.
    pub branch: Option<String>,
    /// Whether the working directory is clean.
    pub is_clean: bool,
}

/// Result of git diff operation for a single file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitDiffResult {
    /// File path.
    pub file_path: String,
    /// Diff content in unified format.
    pub diff: String,
    /// Whether the file is binary.
    pub is_binary: bool,
    /// Whether the diff was truncated.
    pub is_truncated: bool,
    /// Number of additions.
    pub additions: u32,
    /// Number of deletions.
    pub deletions: u32,
}

/// A git commit entry for history display.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitCommit {
    /// Full SHA hash.
    pub oid: String,
    /// Short SHA hash (7 characters).
    pub short_oid: String,
    /// Full commit message.
    pub message: String,
    /// First line of commit message.
    pub summary: String,
    /// Author name.
    pub author_name: String,
    /// Author email.
    pub author_email: String,
    /// Author timestamp (Unix seconds).
    pub author_time: i64,
    /// Committer name.
    pub committer_name: String,
    /// Committer timestamp (Unix seconds).
    pub committer_time: i64,
    /// Parent commit OIDs (for graph visualization).
    pub parent_oids: Vec<String>,
}

/// A git branch entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBranch {
    /// Branch name (without refs/heads/ prefix).
    pub name: String,
    /// Whether this is the currently checked out branch.
    pub is_current: bool,
    /// Whether this is a remote-tracking branch.
    pub is_remote: bool,
    /// Upstream branch name if set.
    pub upstream: Option<String>,
    /// Number of commits ahead of upstream.
    pub ahead: u32,
    /// Number of commits behind upstream.
    pub behind: u32,
    /// OID of the branch's HEAD commit.
    pub head_oid: String,
}

/// Result of git log operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitLogResult {
    /// List of commits.
    pub commits: Vec<GitCommit>,
    /// Whether there are more commits beyond the limit.
    pub has_more: bool,
    /// Total count if available (may be expensive to compute).
    pub total_count: Option<u32>,
}

/// Result of git branches operation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitBranchesResult {
    /// List of local branches.
    pub local: Vec<GitBranch>,
    /// List of remote-tracking branches.
    pub remote: Vec<GitBranch>,
    /// Current branch name.
    pub current: Option<String>,
}

/// Get the git status for a repository.
pub fn get_status(repo_path: &Path) -> Result<GitStatusResult, String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    // Get current branch
    let branch = repo
        .head()
        .ok()
        .and_then(|head| head.shorthand().map(String::from));

    // Get file statuses
    let mut status_opts = StatusOptions::new();
    status_opts
        .include_untracked(true)
        .recurse_untracked_dirs(true)
        .include_ignored(false)
        .include_unmodified(false);

    let statuses = repo
        .statuses(Some(&mut status_opts))
        .map_err(|e| format!("Failed to get status: {}", e))?;

    let mut files = Vec::new();
    for entry in statuses.iter() {
        let path = entry.path().unwrap_or("").to_string();
        let status = entry.status();

        // Determine if file is staged (in index) or unstaged (in workdir)
        let (file_status, staged) = if status.is_index_new() {
            (GitFileStatus::Added, true)
        } else if status.is_index_modified() {
            (GitFileStatus::Modified, true)
        } else if status.is_index_deleted() {
            (GitFileStatus::Deleted, true)
        } else if status.is_index_renamed() {
            (GitFileStatus::Renamed, true)
        } else if status.is_index_typechange() {
            (GitFileStatus::Typechange, true)
        } else if status.is_wt_new() {
            (GitFileStatus::Untracked, false)
        } else if status.is_wt_modified() {
            (GitFileStatus::Modified, false)
        } else if status.is_wt_deleted() {
            (GitFileStatus::Deleted, false)
        } else if status.is_wt_renamed() {
            (GitFileStatus::Renamed, false)
        } else if status.is_wt_typechange() {
            (GitFileStatus::Typechange, false)
        } else if status.is_conflicted() {
            (GitFileStatus::Conflicted, false)
        } else if status.is_ignored() {
            (GitFileStatus::Ignored, false)
        } else {
            continue; // Skip unchanged files
        };

        files.push(GitStatusFile {
            path,
            status: file_status,
            staged,
        });
    }

    let is_clean = files.is_empty();

    Ok(GitStatusResult {
        files,
        branch,
        is_clean,
    })
}

/// Get the diff for a specific file.
pub fn get_file_diff(
    repo_path: &Path,
    file_path: &str,
    max_lines: Option<usize>,
) -> Result<GitDiffResult, String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    let max_lines = max_lines.unwrap_or(2000);

    // Set up diff options
    let mut diff_opts = DiffOptions::new();
    diff_opts
        .pathspec(file_path)
        .context_lines(3);

    // Get the diff between HEAD and working directory
    let diff = repo
        .diff_index_to_workdir(None, Some(&mut diff_opts))
        .map_err(|e| format!("Failed to get workdir diff: {}", e))?;

    // If no workdir changes, try index to HEAD diff (staged changes)
    let diff = if diff.deltas().count() == 0 {
        let head_tree = repo
            .head()
            .ok()
            .and_then(|head| head.peel_to_tree().ok());

        repo.diff_tree_to_index(head_tree.as_ref(), None, Some(&mut diff_opts))
            .map_err(|e| format!("Failed to get staged diff: {}", e))?
    } else {
        diff
    };

    // Check if file is binary
    let is_binary = diff.deltas().any(|d| d.flags().is_binary());

    if is_binary {
        return Ok(GitDiffResult {
            file_path: file_path.to_string(),
            diff: "(Binary file)".to_string(),
            is_binary: true,
            is_truncated: false,
            additions: 0,
            deletions: 0,
        });
    }

    // Collect diff content
    let mut diff_lines = Vec::new();
    let mut additions = 0u32;
    let mut deletions = 0u32;
    let mut is_truncated = false;

    diff.print(git2::DiffFormat::Patch, |_delta, _hunk, line| {
        if diff_lines.len() >= max_lines {
            is_truncated = true;
            return false;
        }

        let origin = line.origin();
        let content = std::str::from_utf8(line.content()).unwrap_or("");

        match origin {
            '+' => {
                additions += 1;
                diff_lines.push(format!("+{}", content.trim_end()));
            }
            '-' => {
                deletions += 1;
                diff_lines.push(format!("-{}", content.trim_end()));
            }
            ' ' => {
                diff_lines.push(format!(" {}", content.trim_end()));
            }
            'H' => {
                // Hunk header
                diff_lines.push(content.trim_end().to_string());
            }
            'F' => {
                // File header
                diff_lines.push(content.trim_end().to_string());
            }
            _ => {
                diff_lines.push(content.trim_end().to_string());
            }
        }

        true
    })
    .map_err(|e| format!("Failed to print diff: {}", e))?;

    let diff_content = diff_lines.join("\n");

    Ok(GitDiffResult {
        file_path: file_path.to_string(),
        diff: diff_content,
        is_binary: false,
        is_truncated,
        additions,
        deletions,
    })
}

/// Get commit history for a repository.
///
/// # Arguments
/// * `repo_path` - Path to the repository
/// * `limit` - Maximum number of commits to return (default 50)
/// * `offset` - Number of commits to skip (for pagination)
/// * `branch` - Optional branch name to get history for (default: HEAD)
pub fn get_log(
    repo_path: &Path,
    limit: Option<usize>,
    offset: Option<usize>,
    branch: Option<&str>,
) -> Result<GitLogResult, String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    let limit = limit.unwrap_or(50);
    let offset = offset.unwrap_or(0);

    // Get starting point for walk
    let start_oid = if let Some(branch_name) = branch {
        // Try local branch first, then remote
        repo.find_branch(branch_name, BranchType::Local)
            .or_else(|_| repo.find_branch(branch_name, BranchType::Remote))
            .map_err(|e| format!("Failed to find branch '{}': {}", branch_name, e))?
            .get()
            .target()
            .ok_or_else(|| format!("Branch '{}' has no target", branch_name))?
    } else {
        repo.head()
            .map_err(|e| format!("Failed to get HEAD: {}", e))?
            .target()
            .ok_or_else(|| "HEAD has no target".to_string())?
    };

    // Create revision walker
    let mut revwalk = repo
        .revwalk()
        .map_err(|e| format!("Failed to create revwalk: {}", e))?;

    revwalk.push(start_oid).map_err(|e| format!("Failed to push start commit: {}", e))?;
    revwalk.set_sorting(Sort::TIME | Sort::TOPOLOGICAL)
        .map_err(|e| format!("Failed to set sorting: {}", e))?;

    let mut commits = Vec::new();
    let mut skipped = 0;
    let mut has_more = false;

    for oid_result in revwalk {
        let oid = match oid_result {
            Ok(oid) => oid,
            Err(_) => continue,
        };

        // Handle offset
        if skipped < offset {
            skipped += 1;
            continue;
        }

        // Check if we've hit the limit
        if commits.len() >= limit {
            has_more = true;
            break;
        }

        let commit = match repo.find_commit(oid) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let author = commit.author();
        let committer = commit.committer();
        let message = commit.message().unwrap_or("").to_string();
        let summary = commit.summary().unwrap_or("").to_string();

        let parent_oids: Vec<String> = commit
            .parent_ids()
            .map(|id| id.to_string())
            .collect();

        commits.push(GitCommit {
            oid: oid.to_string(),
            short_oid: oid.to_string()[..7.min(oid.to_string().len())].to_string(),
            message,
            summary,
            author_name: author.name().unwrap_or("Unknown").to_string(),
            author_email: author.email().unwrap_or("").to_string(),
            author_time: author.when().seconds(),
            committer_name: committer.name().unwrap_or("Unknown").to_string(),
            committer_time: committer.when().seconds(),
            parent_oids,
        });
    }

    Ok(GitLogResult {
        commits,
        has_more,
        total_count: None, // Computing total count is expensive
    })
}

/// Get all branches for a repository.
pub fn get_branches(repo_path: &Path) -> Result<GitBranchesResult, String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    // Get current branch name
    let current = repo
        .head()
        .ok()
        .and_then(|head| {
            if head.is_branch() {
                head.shorthand().map(String::from)
            } else {
                None
            }
        });

    let mut local_branches = Vec::new();
    let mut remote_branches = Vec::new();

    // Iterate over all branches
    let branches = repo
        .branches(None)
        .map_err(|e| format!("Failed to list branches: {}", e))?;

    for branch_result in branches {
        let (branch, branch_type) = match branch_result {
            Ok(b) => b,
            Err(_) => continue,
        };

        let name = match branch.name() {
            Ok(Some(n)) => n.to_string(),
            _ => continue,
        };

        let is_current = current.as_deref() == Some(&name);
        let is_remote = branch_type == BranchType::Remote;

        // Get HEAD commit OID
        let head_oid = branch
            .get()
            .target()
            .map(|oid| oid.to_string())
            .unwrap_or_default();

        // Get upstream info for local branches
        let (upstream, ahead, behind) = if !is_remote {
            match branch.upstream() {
                Ok(upstream_branch) => {
                    let upstream_name = upstream_branch
                        .name()
                        .ok()
                        .flatten()
                        .map(String::from);

                    // Calculate ahead/behind
                    let (ahead, behind) = if let (Some(local_oid), Some(upstream_oid)) = (
                        branch.get().target(),
                        upstream_branch.get().target(),
                    ) {
                        repo.graph_ahead_behind(local_oid, upstream_oid)
                            .map(|(a, b)| (a as u32, b as u32))
                            .unwrap_or((0, 0))
                    } else {
                        (0, 0)
                    };

                    (upstream_name, ahead, behind)
                }
                Err(_) => (None, 0, 0),
            }
        } else {
            (None, 0, 0)
        };

        let git_branch = GitBranch {
            name,
            is_current,
            is_remote,
            upstream,
            ahead,
            behind,
            head_oid,
        };

        if is_remote {
            remote_branches.push(git_branch);
        } else {
            local_branches.push(git_branch);
        }
    }

    // Sort branches: current first, then alphabetically
    local_branches.sort_by(|a, b| {
        match (a.is_current, b.is_current) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.name.cmp(&b.name),
        }
    });
    remote_branches.sort_by(|a, b| a.name.cmp(&b.name));

    Ok(GitBranchesResult {
        local: local_branches,
        remote: remote_branches,
        current,
    })
}

/// Stage files for commit.
pub fn stage_files(repo_path: &Path, paths: &[&str]) -> Result<(), String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    let mut index = repo
        .index()
        .map_err(|e| format!("Failed to get index: {}", e))?;

    for path in paths {
        // Check if file exists - if not, it might be a deletion
        let full_path = repo_path.join(path);
        if full_path.exists() {
            index
                .add_path(Path::new(path))
                .map_err(|e| format!("Failed to stage '{}': {}", path, e))?;
        } else {
            // File was deleted, remove from index
            index
                .remove_path(Path::new(path))
                .map_err(|e| format!("Failed to stage deletion '{}': {}", path, e))?;
        }
    }

    index
        .write()
        .map_err(|e| format!("Failed to write index: {}", e))?;

    Ok(())
}

/// Unstage files (remove from index, keep working tree changes).
pub fn unstage_files(repo_path: &Path, paths: &[&str]) -> Result<(), String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    // Get HEAD tree to reset to
    let head = repo.head().ok();
    let head_tree = head.as_ref().and_then(|h| h.peel_to_tree().ok());

    for path in paths {
        if let Some(ref tree) = head_tree {
            // Reset path to HEAD state in index
            repo.reset_default(Some(&tree.as_object()), &[Path::new(path)])
                .map_err(|e| format!("Failed to unstage '{}': {}", path, e))?;
        } else {
            // No HEAD (initial commit), remove from index
            let mut index = repo
                .index()
                .map_err(|e| format!("Failed to get index: {}", e))?;
            index
                .remove_path(Path::new(path))
                .map_err(|e| format!("Failed to unstage '{}': {}", path, e))?;
            index
                .write()
                .map_err(|e| format!("Failed to write index: {}", e))?;
        }
    }

    Ok(())
}

/// Discard working tree changes for files.
pub fn discard_changes(repo_path: &Path, paths: &[&str]) -> Result<(), String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    let mut checkout_opts = git2::build::CheckoutBuilder::new();
    checkout_opts.force();

    for path in paths {
        checkout_opts.path(path);
    }

    repo.checkout_head(Some(&mut checkout_opts))
        .map_err(|e| format!("Failed to discard changes: {}", e))?;

    Ok(())
}

/// Create a git worktree at `<repo>/.unbound-worktrees/<worktree_name>/`.
///
/// # Arguments
/// * `repo_path` - Path to the main repository
/// * `worktree_name` - Name for the worktree directory (typically session ID)
/// * `branch_name` - Optional branch name to use (defaults to `unbound/<worktree_name>`)
///
/// # Returns
/// The absolute path to the created worktree directory.
pub fn create_worktree(
    repo_path: &Path,
    worktree_name: &str,
    branch_name: Option<&str>,
) -> Result<String, String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    // Construct worktree path: <repo>/.unbound-worktrees/<worktree_name>/
    let worktrees_dir = repo_path.join(".unbound-worktrees");
    let worktree_path = worktrees_dir.join(worktree_name);

    // Create the .unbound-worktrees directory if it doesn't exist
    std::fs::create_dir_all(&worktrees_dir)
        .map_err(|e| format!("Failed to create worktrees directory: {}", e))?;

    // Check if worktree path already exists
    if worktree_path.exists() {
        return Err(format!(
            "Worktree directory already exists: {}",
            worktree_path.display()
        ));
    }

    // Determine branch name
    let branch = branch_name
        .map(String::from)
        .unwrap_or_else(|| format!("unbound/{}", worktree_name));

    // Get HEAD commit to create branch from
    let head = repo.head().map_err(|e| format!("Failed to get HEAD: {}", e))?;
    let head_commit = head
        .peel_to_commit()
        .map_err(|e| format!("Failed to get HEAD commit: {}", e))?;

    // Check if branch already exists
    let branch_ref = match repo.find_branch(&branch, BranchType::Local) {
        Ok(existing_branch) => {
            // Branch exists, use it
            existing_branch
                .into_reference()
                .name()
                .map(String::from)
                .ok_or_else(|| "Branch reference has no name".to_string())?
        }
        Err(_) => {
            // Create new branch from HEAD
            let new_branch = repo
                .branch(&branch, &head_commit, false)
                .map_err(|e| format!("Failed to create branch '{}': {}", branch, e))?;
            new_branch
                .into_reference()
                .name()
                .map(String::from)
                .ok_or_else(|| "Branch reference has no name".to_string())?
        }
    };

    // Create the worktree
    repo.worktree(
        worktree_name,
        &worktree_path,
        Some(
            git2::WorktreeAddOptions::new()
                .reference(Some(&repo.find_reference(&branch_ref).map_err(|e| {
                    format!("Failed to find branch reference: {}", e)
                })?)),
        ),
    )
    .map_err(|e| format!("Failed to create worktree: {}", e))?;

    // Return the absolute path
    let abs_path = worktree_path
        .canonicalize()
        .unwrap_or(worktree_path)
        .to_string_lossy()
        .to_string();

    Ok(abs_path)
}

/// Remove a git worktree and its directory.
///
/// # Arguments
/// * `repo_path` - Path to the main repository
/// * `worktree_path` - Path to the worktree directory to remove
///
/// # Returns
/// Ok(()) on success, Err with message on failure.
pub fn remove_worktree(repo_path: &Path, worktree_path: &Path) -> Result<(), String> {
    let repo = Repository::open(repo_path)
        .map_err(|e| format!("Failed to open repository: {}", e))?;

    // Try to find the worktree name from the path
    let worktree_name = worktree_path
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or_else(|| "Invalid worktree path".to_string())?;

    // Check if worktree exists in git
    if let Ok(worktree) = repo.find_worktree(worktree_name) {
        // Prune the worktree from git's tracking
        // Note: git2 doesn't have a direct "remove worktree" API,
        // so we need to prune it and then clean up the directory
        worktree
            .prune(Some(
                git2::WorktreePruneOptions::new()
                    .working_tree(true)
                    .valid(true),
            ))
            .map_err(|e| format!("Failed to prune worktree: {}", e))?;
    }

    // Remove the worktree directory if it exists
    if worktree_path.exists() {
        std::fs::remove_dir_all(worktree_path)
            .map_err(|e| format!("Failed to remove worktree directory: {}", e))?;
    }

    // Clean up the .unbound-worktrees directory if empty
    if let Some(parent) = worktree_path.parent() {
        if parent.file_name().map(|n| n == ".unbound-worktrees").unwrap_or(false) {
            // Try to remove if empty, ignore errors
            let _ = std::fs::remove_dir(parent);
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_git_file_status_from_delta() {
        assert_eq!(GitFileStatus::from_delta(Delta::Added), GitFileStatus::Added);
        assert_eq!(GitFileStatus::from_delta(Delta::Deleted), GitFileStatus::Deleted);
        assert_eq!(GitFileStatus::from_delta(Delta::Modified), GitFileStatus::Modified);
        assert_eq!(GitFileStatus::from_delta(Delta::Untracked), GitFileStatus::Untracked);
    }

    #[test]
    fn test_get_status_non_repo() {
        let result = get_status(Path::new("/tmp"));
        assert!(result.is_err());
    }

    #[test]
    fn test_get_status_current_repo() {
        // This test runs against the actual repository
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let repo_path = manifest_dir
            .parent()
            .and_then(|p| p.parent())
            .and_then(|p| p.parent())
            .unwrap();

        let result = get_status(repo_path);
        assert!(result.is_ok());

        let status = result.unwrap();
        assert!(status.branch.is_some());
    }

    #[test]
    fn test_get_file_diff_non_repo() {
        let result = get_file_diff(Path::new("/tmp"), "nonexistent.txt", None);
        assert!(result.is_err());
    }
}
