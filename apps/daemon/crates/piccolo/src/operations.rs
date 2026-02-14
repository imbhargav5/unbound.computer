//! Git operations implementation.
//!
//! All operations are pure functions that take a repository path and return
//! results. They do not maintain any state between calls.

use git2::{BranchType, DiffOptions, Repository, Sort, StatusOptions};
use std::path::{Path, PathBuf};

use crate::error::PiccoloError;
use crate::types::{
    GitBranch, GitBranchesResult, GitCommit, GitCommitResult, GitDiffResult, GitFileStatus,
    GitLogResult, GitPushResult, GitStatusFile, GitStatusResult,
};

/// Get the git status for a repository.
///
/// Queries both the index (staged changes) and working tree (unstaged changes)
/// to provide a complete picture of the repository state.
///
/// # Arguments
///
/// * `repo_path` - Path to the repository root (containing .git directory)
///
/// # Returns
///
/// A [`GitStatusResult`] containing:
/// - List of changed files with their status and staged state
/// - Current branch name (or None if detached HEAD)
/// - Whether the working directory is clean
///
/// # Errors
///
/// Returns an error if:
/// - The path is not a git repository
/// - The repository cannot be opened
/// - Status query fails
///
/// # Example
///
/// ```ignore
/// let status = get_status(Path::new("/path/to/repo"))?;
/// for file in &status.files {
///     let state = if file.staged { "staged" } else { "unstaged" };
///     println!("{}: {:?} ({})", file.path, file.status, state);
/// }
/// ```
pub fn get_status(repo_path: &Path) -> Result<GitStatusResult, String> {
    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

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

        // Check for staged (index) changes
        let index_status = if status.is_index_new() {
            Some(GitFileStatus::Added)
        } else if status.is_index_modified() {
            Some(GitFileStatus::Modified)
        } else if status.is_index_deleted() {
            Some(GitFileStatus::Deleted)
        } else if status.is_index_renamed() {
            Some(GitFileStatus::Renamed)
        } else if status.is_index_typechange() {
            Some(GitFileStatus::Typechange)
        } else {
            None
        };

        // Check for unstaged (working tree) changes
        let wt_status = if status.is_wt_new() {
            Some(GitFileStatus::Untracked)
        } else if status.is_wt_modified() {
            Some(GitFileStatus::Modified)
        } else if status.is_wt_deleted() {
            Some(GitFileStatus::Deleted)
        } else if status.is_wt_renamed() {
            Some(GitFileStatus::Renamed)
        } else if status.is_wt_typechange() {
            Some(GitFileStatus::Typechange)
        } else {
            None
        };

        // Emit staged entry if present
        if let Some(file_status) = index_status {
            files.push(GitStatusFile {
                path: path.clone(),
                status: file_status,
                staged: true,
            });
        }

        // Emit unstaged entry if present
        if let Some(file_status) = wt_status {
            files.push(GitStatusFile {
                path: path.clone(),
                status: file_status,
                staged: false,
            });
        }

        // Handle conflicted and ignored (not index or wt specific)
        if index_status.is_none() && wt_status.is_none() {
            if status.is_conflicted() {
                files.push(GitStatusFile {
                    path,
                    status: GitFileStatus::Conflicted,
                    staged: false,
                });
            } else if status.is_ignored() {
                files.push(GitStatusFile {
                    path,
                    status: GitFileStatus::Ignored,
                    staged: false,
                });
            }
        }
    }

    let is_clean = files.is_empty();

    Ok(GitStatusResult {
        files,
        branch,
        is_clean,
    })
}

/// Get the diff for a specific file.
///
/// Generates a unified diff for the specified file, comparing either:
/// - Working tree changes (unstaged) against the index
/// - Index changes (staged) against HEAD
///
/// # Arguments
///
/// * `repo_path` - Path to the repository root
/// * `file_path` - Path to the file relative to repository root
/// * `max_lines` - Maximum number of diff lines to return (default: 2000)
///
/// # Returns
///
/// A [`GitDiffResult`] containing:
/// - The unified diff content
/// - Binary file indicator
/// - Truncation indicator
/// - Addition/deletion counts
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - The file does not exist or has no changes
/// - Diff generation fails
///
/// # Example
///
/// ```ignore
/// let diff = get_file_diff(repo_path, "src/main.rs", Some(500))?;
/// if diff.is_binary {
///     println!("Binary file");
/// } else {
///     println!("+{} -{}", diff.additions, diff.deletions);
///     println!("{}", diff.diff);
/// }
/// ```
pub fn get_file_diff(
    repo_path: &Path,
    file_path: &str,
    max_lines: Option<usize>,
) -> Result<GitDiffResult, String> {
    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

    let max_lines = max_lines.unwrap_or(2000);

    // Set up diff options
    let mut diff_opts = DiffOptions::new();
    diff_opts.pathspec(file_path).context_lines(3);

    // Get the diff between HEAD and working directory
    let diff = repo
        .diff_index_to_workdir(None, Some(&mut diff_opts))
        .map_err(|e| format!("Failed to get workdir diff: {}", e))?;

    // If no workdir changes, try index to HEAD diff (staged changes)
    let diff = if diff.deltas().count() == 0 {
        let head_tree = repo.head().ok().and_then(|head| head.peel_to_tree().ok());

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
/// Retrieves commits in reverse chronological order with support for
/// pagination and branch filtering.
///
/// # Arguments
///
/// * `repo_path` - Path to the repository
/// * `limit` - Maximum number of commits to return (default: 50)
/// * `offset` - Number of commits to skip for pagination (default: 0)
/// * `branch` - Optional branch name to get history for (default: HEAD)
///
/// # Returns
///
/// A [`GitLogResult`] containing:
/// - List of commits with full metadata
/// - Whether more commits exist beyond the limit
/// - Total count (typically None for performance)
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - The specified branch does not exist
/// - Revision walking fails
///
/// # Example
///
/// ```ignore
/// // Get first 20 commits
/// let log = get_log(repo_path, Some(20), None, None)?;
/// for commit in &log.commits {
///     println!("{} {}", commit.short_oid, commit.summary);
/// }
///
/// // Get next 20 commits (pagination)
/// if log.has_more {
///     let page2 = get_log(repo_path, Some(20), Some(20), None)?;
/// }
/// ```
pub fn get_log(
    repo_path: &Path,
    limit: Option<usize>,
    offset: Option<usize>,
    branch: Option<&str>,
) -> Result<GitLogResult, String> {
    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

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

    revwalk
        .push(start_oid)
        .map_err(|e| format!("Failed to push start commit: {}", e))?;
    revwalk
        .set_sorting(Sort::TIME | Sort::TOPOLOGICAL)
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

        let parent_oids: Vec<String> = commit.parent_ids().map(|id| id.to_string()).collect();

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
///
/// Returns both local and remote-tracking branches with their
/// tracking relationships and ahead/behind counts.
///
/// # Arguments
///
/// * `repo_path` - Path to the repository
///
/// # Returns
///
/// A [`GitBranchesResult`] containing:
/// - Local branches with upstream tracking info
/// - Remote-tracking branches
/// - Current branch name
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - Branch enumeration fails
///
/// # Example
///
/// ```ignore
/// let branches = get_branches(repo_path)?;
///
/// println!("Current: {:?}", branches.current);
///
/// for branch in &branches.local {
///     let tracking = match &branch.upstream {
///         Some(u) => format!(" (tracking {} +{} -{})", u, branch.ahead, branch.behind),
///         None => String::new(),
///     };
///     println!("  {}{}", branch.name, tracking);
/// }
/// ```
pub fn get_branches(repo_path: &Path) -> Result<GitBranchesResult, String> {
    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

    // Get current branch name
    let current = repo.head().ok().and_then(|head| {
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
                    let upstream_name = upstream_branch.name().ok().flatten().map(String::from);

                    // Calculate ahead/behind
                    let (ahead, behind) = if let (Some(local_oid), Some(upstream_oid)) =
                        (branch.get().target(), upstream_branch.get().target())
                    {
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
    local_branches.sort_by(|a, b| match (a.is_current, b.is_current) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => a.name.cmp(&b.name),
    });
    remote_branches.sort_by(|a, b| a.name.cmp(&b.name));

    Ok(GitBranchesResult {
        local: local_branches,
        remote: remote_branches,
        current,
    })
}

/// Stage files for commit.
///
/// Adds files to the git index (staging area). Handles both new files
/// and deleted files appropriately.
///
/// # Arguments
///
/// * `repo_path` - Path to the repository
/// * `paths` - Slice of file paths relative to repository root
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - Any file cannot be staged
/// - Index write fails
///
/// # Example
///
/// ```ignore
/// // Stage specific files
/// stage_files(repo_path, &["src/main.rs", "Cargo.toml"])?;
///
/// // Stage a deleted file
/// stage_files(repo_path, &["removed_file.rs"])?;
/// ```
pub fn stage_files(repo_path: &Path, paths: &[&str]) -> Result<(), String> {
    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

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
///
/// Resets files in the index to their HEAD state while preserving
/// any working tree modifications.
///
/// # Arguments
///
/// * `repo_path` - Path to the repository
/// * `paths` - Slice of file paths relative to repository root
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - Any file cannot be unstaged
/// - Index write fails
///
/// # Example
///
/// ```ignore
/// // Unstage specific files
/// unstage_files(repo_path, &["src/main.rs"])?;
/// ```
pub fn unstage_files(repo_path: &Path, paths: &[&str]) -> Result<(), String> {
    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

    // Get HEAD commit to reset to (reset_default requires a commit-ish object)
    let head = repo.head().ok();
    let head_commit = head.as_ref().and_then(|h| h.peel_to_commit().ok());

    for path in paths {
        if let Some(ref commit) = head_commit {
            // Reset path to HEAD state in index
            repo.reset_default(Some(commit.as_object()), &[Path::new(path)])
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
///
/// Resets files in the working tree to match their state in the index.
/// This is a destructive operation that cannot be undone.
///
/// # Arguments
///
/// * `repo_path` - Path to the repository
/// * `paths` - Slice of file paths relative to repository root
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - Checkout operation fails
///
/// # Warning
///
/// This operation permanently discards uncommitted changes. There is
/// no way to recover discarded changes unless they were stashed or
/// backed up elsewhere.
///
/// # Example
///
/// ```ignore
/// // Discard changes to specific files
/// discard_changes(repo_path, &["src/main.rs"])?;
/// ```
pub fn discard_changes(repo_path: &Path, paths: &[&str]) -> Result<(), String> {
    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

    let mut checkout_opts = git2::build::CheckoutBuilder::new();
    checkout_opts.force();

    for path in paths {
        checkout_opts.path(path);
    }

    repo.checkout_head(Some(&mut checkout_opts))
        .map_err(|e| format!("Failed to discard changes: {}", e))?;

    Ok(())
}

/// Create a git commit from staged changes.
///
/// Creates a new commit with the given message using the staged changes
/// in the index. If author name/email are not provided, they are read
/// from the repository's git configuration.
///
/// # Arguments
///
/// * `repo_path` - Path to the repository
/// * `message` - Commit message
/// * `author_name` - Optional author name (defaults to git config user.name)
/// * `author_email` - Optional author email (defaults to git config user.email)
///
/// # Returns
///
/// A [`GitCommitResult`] with the new commit's OID and summary.
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - There are no staged changes
/// - Author information is not available
/// - Commit creation fails
pub fn commit(
    repo_path: &Path,
    message: &str,
    author_name: Option<&str>,
    author_email: Option<&str>,
) -> Result<GitCommitResult, PiccoloError> {
    let repo = Repository::open(repo_path)?;

    let mut index = repo
        .index()
        .map_err(|e| PiccoloError::IndexAccess(e.message().to_string()))?;

    // Write the index as a tree
    let tree_oid = index
        .write_tree()
        .map_err(|e| PiccoloError::IndexAccess(e.message().to_string()))?;
    let tree = repo
        .find_tree(tree_oid)
        .map_err(|e| PiccoloError::CommitCreation(e.message().to_string()))?;

    // Check if there are actually staged changes by comparing tree to HEAD
    let head_tree = repo.head().ok().and_then(|head| head.peel_to_tree().ok());

    if let Some(ref ht) = head_tree {
        let diff = repo
            .diff_tree_to_tree(Some(ht), Some(&tree), None)
            .map_err(|e| PiccoloError::CommitCreation(e.message().to_string()))?;
        if diff.deltas().count() == 0 {
            return Err(PiccoloError::NothingToCommit);
        }
    }

    // Get author info from params or git config
    let config = repo
        .config()
        .map_err(|e| PiccoloError::CommitCreation(e.message().to_string()))?;

    let name = match author_name {
        Some(n) => n.to_string(),
        None => config
            .get_string("user.name")
            .map_err(|_| PiccoloError::CommitCreation("user.name not configured".to_string()))?,
    };

    let email = match author_email {
        Some(e) => e.to_string(),
        None => config
            .get_string("user.email")
            .map_err(|_| PiccoloError::CommitCreation("user.email not configured".to_string()))?,
    };

    let signature = git2::Signature::now(&name, &email)
        .map_err(|e| PiccoloError::CommitCreation(e.message().to_string()))?;

    // Get parent commit (if any)
    let parent_commit = repo.head().ok().and_then(|head| head.peel_to_commit().ok());
    let parents: Vec<&git2::Commit> = parent_commit.iter().collect();

    let commit_oid = repo
        .commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        )
        .map_err(|e| PiccoloError::CommitCreation(e.message().to_string()))?;

    let oid_str = commit_oid.to_string();
    let short_oid = oid_str[..7.min(oid_str.len())].to_string();
    let summary = message.lines().next().unwrap_or("").to_string();

    Ok(GitCommitResult {
        oid: oid_str,
        short_oid,
        summary,
    })
}

/// Push commits to a remote repository.
///
/// Shells out to `git push` to inherit the user's credential infrastructure
/// (SSH keys, macOS Keychain, credential helpers).
///
/// # Arguments
///
/// * `repo_path` - Path to the repository
/// * `remote` - Optional remote name (defaults to "origin")
/// * `branch` - Optional branch name (defaults to current branch)
///
/// # Returns
///
/// A [`GitPushResult`] with the remote and branch that were pushed.
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - No current branch is checked out
/// - Authentication fails
/// - The remote is not found
/// - The push is rejected
pub fn push(
    repo_path: &Path,
    remote: Option<&str>,
    branch: Option<&str>,
) -> Result<GitPushResult, PiccoloError> {
    // Validate repo exists and get defaults
    let repo = Repository::open(repo_path)?;

    let remote_name = remote.unwrap_or("origin").to_string();

    let branch_name = match branch {
        Some(b) => b.to_string(),
        None => repo
            .head()
            .ok()
            .and_then(|head| {
                if head.is_branch() {
                    head.shorthand().map(String::from)
                } else {
                    None
                }
            })
            .ok_or_else(|| {
                PiccoloError::PushFailed("No branch currently checked out".to_string())
            })?,
    };

    // Drop the repo before spawning git to release any locks
    drop(repo);

    let output = std::process::Command::new("git")
        .args(["push", &remote_name, &branch_name])
        .current_dir(repo_path)
        .output()
        .map_err(|e| PiccoloError::PushFailed(format!("Failed to execute git push: {}", e)))?;

    if output.status.success() {
        return Ok(GitPushResult {
            remote: remote_name,
            branch: branch_name,
            success: true,
        });
    }

    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    // Categorize the error
    let stderr_lower = stderr.to_lowercase();
    if stderr_lower.contains("authentication")
        || stderr_lower.contains("permission denied")
        || stderr_lower.contains("could not read")
        || stderr_lower.contains("403")
        || stderr_lower.contains("401")
    {
        return Err(PiccoloError::AuthRequired(remote_name));
    }

    if stderr_lower.contains("does not appear to be a git repository")
        || stderr_lower.contains("repository not found")
    {
        return Err(PiccoloError::RemoteNotFound(remote_name));
    }

    if stderr_lower.contains("everything up-to-date") {
        return Ok(GitPushResult {
            remote: remote_name,
            branch: branch_name,
            success: true,
        });
    }

    Err(PiccoloError::PushFailed(stderr))
}

const DEFAULT_WORKTREE_ROOT_DIR_TEMPLATE: &str = "~/.unbound/{repo_id}/worktrees";

fn expand_home_dir(path: &Path) -> PathBuf {
    let Some(raw_path) = path.to_str() else {
        return path.to_path_buf();
    };

    if raw_path == "~" {
        return std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| path.to_path_buf());
    }

    if let Some(suffix) = raw_path.strip_prefix("~/") {
        return std::env::var("HOME")
            .map(|home| PathBuf::from(home).join(suffix))
            .unwrap_or_else(|_| path.to_path_buf());
    }

    path.to_path_buf()
}

fn resolve_worktrees_dir(repo_path: &Path, root_dir: &Path) -> PathBuf {
    let resolved_root = expand_home_dir(root_dir);

    if resolved_root.is_absolute() {
        resolved_root
    } else {
        repo_path.join(resolved_root)
    }
}

fn default_worktree_root_dir_for_repo(repository_id: &str) -> Result<String, String> {
    let trimmed = repository_id.trim();
    if trimmed.is_empty() {
        return Err("Invalid repository id: cannot be empty or whitespace".to_string());
    }
    if trimmed != repository_id {
        return Err(
            "Invalid repository id: leading or trailing whitespace is not allowed".to_string(),
        );
    }

    Ok(DEFAULT_WORKTREE_ROOT_DIR_TEMPLATE.replace("{repo_id}", trimmed))
}

fn validate_worktree_name(worktree_name: &str) -> Result<(), String> {
    let trimmed = worktree_name.trim();
    if trimmed.is_empty() {
        return Err("Invalid worktree name: cannot be empty or whitespace".to_string());
    }
    if trimmed != worktree_name {
        return Err(
            "Invalid worktree name: leading or trailing whitespace is not allowed".to_string(),
        );
    }
    if trimmed.contains('/') || trimmed.contains('\\') {
        return Err("Invalid worktree name: path separators are not allowed".to_string());
    }
    if trimmed == "." {
        return Err("Invalid worktree name: '.' is not allowed".to_string());
    }
    if trimmed.contains("..") {
        return Err("Invalid worktree name: '..' is not allowed".to_string());
    }
    if !trimmed
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.')
    {
        return Err(
            "Invalid worktree name: only ASCII letters, numbers, '.', '_', and '-' are allowed"
                .to_string(),
        );
    }
    Ok(())
}

fn resolve_base_commit<'repo>(
    repo: &'repo Repository,
    base_branch: &str,
) -> Result<git2::Commit<'repo>, String> {
    let base_object = repo
        .revparse_single(base_branch)
        .or_else(|_| repo.revparse_single(&format!("refs/heads/{}", base_branch)))
        .or_else(|_| repo.revparse_single(&format!("refs/remotes/{}", base_branch)))
        .map_err(|e| {
            format!(
                "Failed to resolve base branch reference '{}': {}",
                base_branch, e
            )
        })?;

    base_object
        .peel_to_commit()
        .map_err(|e| format!("Failed to resolve base commit '{}': {}", base_branch, e))
}

/// Create a git worktree at `<root_dir>/<worktree_name>/`.
///
/// Creates a linked worktree with a corresponding branch for parallel
/// development workflows.
///
/// # Arguments
///
/// * `repo_path` - Path to the main repository
/// * `worktree_name` - Name for the worktree directory (typically session ID)
/// * `root_dir` - Root worktree directory, absolute or relative to `repo_path`
/// * `base_branch` - Optional branch/ref to create a new worktree branch from (defaults to `HEAD`)
/// * `worktree_branch` - Optional branch name to use (defaults to `unbound/<worktree_name>`)
///
/// # Returns
///
/// The absolute path to the created worktree directory.
///
/// # Worktree Layout
///
/// ```text
/// /Users/alice/.unbound/repo-123/worktrees/
/// └── session-123/              <- Created worktree
///     ├── .git                  <- File pointing to main repo .git
///     └── ...                   <- Working tree files
/// ```
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - The worktree directory already exists
/// - Branch creation fails
/// - Worktree creation fails
///
/// # Example
///
/// ```ignore
/// let path = create_worktree_with_options(
///     repo_path,
///     "session-123",
///     Path::new("~/.unbound/repo-123/worktrees"),
///     Some("origin/main"),
///     None,
/// )?;
/// println!("Worktree created at: {}", path);
///
/// // With custom branch name
/// let path = create_worktree_with_options(
///     repo_path,
///     "feature",
///     Path::new("~/.unbound/repo-123/worktrees"),
///     None,
///     Some("feature/my-feature"),
/// )?;
/// ```
pub fn create_worktree_with_options(
    repo_path: &Path,
    worktree_name: &str,
    root_dir: &Path,
    base_branch: Option<&str>,
    worktree_branch: Option<&str>,
) -> Result<String, String> {
    validate_worktree_name(worktree_name)?;

    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

    let worktrees_dir = resolve_worktrees_dir(repo_path, root_dir);
    let worktree_path = worktrees_dir.join(worktree_name);

    std::fs::create_dir_all(&worktrees_dir)
        .map_err(|e| format!("Failed to create worktrees directory: {}", e))?;

    // Check if worktree path already exists
    if worktree_path.exists() {
        return Err(format!(
            "Worktree directory already exists: {}",
            worktree_path.display()
        ));
    }

    // Determine target branch name
    let branch = worktree_branch
        .map(String::from)
        .unwrap_or_else(|| format!("unbound/{}", worktree_name));

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
            let base_commit = match base_branch {
                Some(base_branch) => resolve_base_commit(&repo, base_branch)?,
                None => {
                    let head = repo
                        .head()
                        .map_err(|e| format!("Failed to get HEAD: {}", e))?;
                    head.peel_to_commit()
                        .map_err(|e| format!("Failed to get HEAD commit: {}", e))?
                }
            };

            // Create new branch from resolved base commit.
            let new_branch = repo
                .branch(&branch, &base_commit, false)
                .map_err(|e| format!("Failed to create branch '{}': {}", branch, e))?;
            new_branch
                .into_reference()
                .name()
                .map(String::from)
                .ok_or_else(|| "Branch reference has no name".to_string())?
        }
    };

    // Create the worktree
    let branch_reference = repo
        .find_reference(&branch_ref)
        .map_err(|e| format!("Failed to find branch reference: {}", e))?;
    let mut add_options = git2::WorktreeAddOptions::new();
    add_options.reference(Some(&branch_reference));
    repo.worktree(worktree_name, &worktree_path, Some(&add_options))
        .map_err(|e| format!("Failed to create worktree: {}", e))?;

    // Return the absolute path
    let abs_path = worktree_path
        .canonicalize()
        .unwrap_or(worktree_path)
        .to_string_lossy()
        .to_string();

    Ok(abs_path)
}

/// Backward-compatible wrapper around [`create_worktree_with_options`].
///
/// Defaults to `~/.unbound/<repository_id>/worktrees` and `HEAD` as base branch.
pub fn create_worktree(
    repo_path: &Path,
    repository_id: &str,
    worktree_name: &str,
    branch_name: Option<&str>,
) -> Result<String, String> {
    let default_root_dir = default_worktree_root_dir_for_repo(repository_id)?;
    create_worktree_with_options(
        repo_path,
        worktree_name,
        Path::new(&default_root_dir),
        None,
        branch_name,
    )
}

/// Remove a git worktree and its directory.
///
/// Cleans up both the worktree registration in git and the worktree
/// directory on disk.
///
/// # Arguments
///
/// * `repo_path` - Path to the main repository
/// * `worktree_path` - Path to the worktree directory to remove
///
/// # Errors
///
/// Returns an error if:
/// - The repository cannot be opened
/// - Worktree pruning fails
/// - Directory removal fails
///
/// # Example
///
/// ```ignore
/// remove_worktree(repo_path, Path::new("/Users/alice/.unbound/repo-123/worktrees/session-123"))?;
/// ```
pub fn remove_worktree(repo_path: &Path, worktree_path: &Path) -> Result<(), String> {
    let repo =
        Repository::open(repo_path).map_err(|e| format!("Failed to open repository: {}", e))?;

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

    // Clean up parent worktree folders if they are now empty.
    if let Some(parent) = worktree_path.parent() {
        // Try to remove the direct parent first, ignore errors.
        let _ = std::fs::remove_dir(parent);

        // If we are under `.unbound/worktrees`, also attempt to remove `.unbound`.
        if parent
            .file_name()
            .map(|n| n == "worktrees")
            .unwrap_or(false)
        {
            if let Some(grandparent) = parent.parent() {
                if grandparent
                    .file_name()
                    .map(|n| n == ".unbound")
                    .unwrap_or(false)
                {
                    // Remove only if empty, ignore errors.
                    let _ = std::fs::remove_dir(grandparent);
                }
            }
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
        use git2::Delta;
        assert_eq!(
            GitFileStatus::from_delta(Delta::Added),
            GitFileStatus::Added
        );
        assert_eq!(
            GitFileStatus::from_delta(Delta::Deleted),
            GitFileStatus::Deleted
        );
        assert_eq!(
            GitFileStatus::from_delta(Delta::Modified),
            GitFileStatus::Modified
        );
        assert_eq!(
            GitFileStatus::from_delta(Delta::Untracked),
            GitFileStatus::Untracked
        );
    }

    #[test]
    fn test_validate_worktree_name_accepts_safe_values() {
        let valid = [
            "session-1",
            "unbound_123",
            "release.2026.02",
            "abcDEF-123_.name",
        ];
        for name in valid {
            assert!(
                validate_worktree_name(name).is_ok(),
                "expected valid worktree name: {}",
                name
            );
        }
    }

    #[test]
    fn test_validate_worktree_name_rejects_unsafe_values() {
        let invalid = [
            "",
            "   ",
            " session",
            "session ",
            "foo/bar",
            "foo\\bar",
            ".",
            "..",
            "a..b",
            "semi;colon",
            "emoji-\u{1F680}",
        ];
        for name in invalid {
            assert!(
                validate_worktree_name(name).is_err(),
                "expected invalid worktree name: {:?}",
                name
            );
        }
    }

    #[test]
    fn test_default_worktree_root_dir_for_repo_uses_repo_id() {
        let root = default_worktree_root_dir_for_repo("repo-123").expect("default root");
        assert_eq!(root, "~/.unbound/repo-123/worktrees");
    }

    #[test]
    fn test_default_worktree_root_dir_for_repo_rejects_empty() {
        let err = default_worktree_root_dir_for_repo("   ").expect_err("should reject empty");
        assert!(err.contains("Invalid repository id"));
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
        let repo = match git2::Repository::discover(&manifest_dir) {
            Ok(repo) => repo,
            Err(_) => return, // Not running inside a git repo, skip test.
        };
        let repo_path = match repo.workdir() {
            Some(path) => path,
            None => return, // Bare repo, skip test.
        };

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
