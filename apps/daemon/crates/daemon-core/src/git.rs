//! Git operations using libgit2.
//!
//! Provides native git integration for repository status and diff operations.

use git2::{Delta, DiffOptions, Repository, StatusOptions};
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
