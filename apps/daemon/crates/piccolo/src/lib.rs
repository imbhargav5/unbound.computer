//! # Piccolo: Native Git Operations
//!
//! Piccolo provides native git integration for the Unbound daemon using libgit2.
//! It encapsulates all git operations required for repository status, diffs,
//! commit history, branch management, and worktree operations.
//!
//! ## Overview
//!
//! The crate exposes pure functions that operate on repository paths, making it
//! easy to integrate with any application architecture. All operations are
//! synchronous and designed for single-threaded use within the daemon.
//!
//! ## Key Operations
//!
//! | Function | Description |
//! |----------|-------------|
//! | [`get_status`] | Query working tree and index status |
//! | [`get_file_diff`] | Generate unified diff for a file |
//! | [`get_log`] | Retrieve commit history with pagination |
//! | [`get_branches`] | List all local and remote branches |
//! | [`stage_files`] | Add files to the index |
//! | [`unstage_files`] | Remove files from the index |
//! | [`discard_changes`] | Reset working tree changes |
//! | [`create_worktree`] | Create a linked worktree |
//! | [`remove_worktree`] | Remove a linked worktree |
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                           Daemon                                 │
//! │                                                                  │
//! │  IPC Handler ──► piccolo::get_status() ──► GitStatusResult      │
//! │                                                                  │
//! │  IPC Handler ──► piccolo::get_file_diff() ──► GitDiffResult     │
//! │                                                                  │
//! │  IPC Handler ──► piccolo::get_log() ──► GitLogResult            │
//! │                                                                  │
//! │  IPC Handler ──► piccolo::stage_files() ──► ()                  │
//! │                                                                  │
//! └─────────────────────────────────────────────────────────────────┘
//!                               │
//!                               ▼
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                        libgit2 (git2-rs)                         │
//! │                                                                  │
//! │  Repository, Index, Status, Diff, Revwalk, Worktree             │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Example Usage
//!
//! ```ignore
//! use piccolo::{get_status, get_file_diff, stage_files};
//! use std::path::Path;
//!
//! let repo_path = Path::new("/path/to/repo");
//!
//! // Get repository status
//! let status = get_status(repo_path)?;
//! println!("Branch: {:?}", status.branch);
//! println!("Clean: {}", status.is_clean);
//!
//! for file in &status.files {
//!     println!("  {} {:?} (staged: {})", file.path, file.status, file.staged);
//! }
//!
//! // Get diff for a modified file
//! if let Some(file) = status.files.first() {
//!     let diff = get_file_diff(repo_path, &file.path, None)?;
//!     println!("Diff:\n{}", diff.diff);
//! }
//!
//! // Stage files
//! stage_files(repo_path, &["src/main.rs", "Cargo.toml"])?;
//! ```
//!
//! ## Error Handling
//!
//! All operations return `Result<T, String>` where the error string contains
//! a human-readable description of what went wrong. Common errors include:
//!
//! - Repository not found or not a git repository
//! - Branch not found
//! - File not found
//! - Permission errors
//! - Index write failures
//!
//! ## Worktree Management
//!
//! Piccolo supports creating linked worktrees for parallel development:
//!
//! ```ignore
//! use piccolo::{create_worktree, create_worktree_with_options, remove_worktree};
//! use std::path::Path;
//!
//! let repo_path = Path::new("/path/to/repo");
//!
//! // Create a worktree for a session
//! let worktree_path = create_worktree(repo_path, "repo-123", "session-123", None)?;
//! // Worktree created at (wrapper default): ~/.unbound/repo-123/worktrees/session-123/
//!
//! // Create with explicit root/base/branch options
//! let worktree_path = create_worktree_with_options(
//!     repo_path,
//!     "session-124",
//!     Path::new("~/.unbound/repo-123/worktrees"),
//!     Some("origin/main"),
//!     Some("feature/session-124"),
//! )?;
//!
//! // Later, clean up
//! remove_worktree(repo_path, Path::new(&worktree_path))?;
//! ```
//!
//! Worktrees are created in `~/.unbound/<repo_id>/worktrees/<name>/` with a
//! corresponding branch `unbound/<name>` (or a custom branch name).

mod error;
mod operations;
mod types;

pub use error::PiccoloError;
pub use operations::{
    commit, create_worktree, create_worktree_with_options, discard_changes, get_branches,
    get_file_diff, get_log, get_status, push, remove_worktree, stage_files, unstage_files,
};
pub use types::{
    GitBranch, GitBranchesResult, GitCommit, GitCommitResult, GitDiffResult, GitFileStatus,
    GitLogResult, GitPushResult, GitStatusFile, GitStatusResult,
};
