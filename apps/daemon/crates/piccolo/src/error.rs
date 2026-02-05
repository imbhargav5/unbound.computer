//! Error types for Piccolo git operations.

use thiserror::Error;

/// Errors that can occur during git operations.
#[derive(Debug, Error)]
pub enum PiccoloError {
    /// Failed to open the repository.
    #[error("Failed to open repository: {0}")]
    RepositoryOpen(String),

    /// Failed to get repository HEAD.
    #[error("Failed to get HEAD: {0}")]
    HeadAccess(String),

    /// Failed to access the git index.
    #[error("Failed to access index: {0}")]
    IndexAccess(String),

    /// Failed to write to the git index.
    #[error("Failed to write index: {0}")]
    IndexWrite(String),

    /// Failed to get repository status.
    #[error("Failed to get status: {0}")]
    StatusQuery(String),

    /// Failed to generate diff.
    #[error("Failed to generate diff: {0}")]
    DiffGeneration(String),

    /// Branch not found.
    #[error("Branch not found: {0}")]
    BranchNotFound(String),

    /// Failed to list branches.
    #[error("Failed to list branches: {0}")]
    BranchList(String),

    /// Failed to create branch.
    #[error("Failed to create branch: {0}")]
    BranchCreate(String),

    /// Failed to create revision walker.
    #[error("Failed to create revision walker: {0}")]
    RevwalkCreate(String),

    /// Failed to stage file.
    #[error("Failed to stage file '{0}': {1}")]
    StageFile(String, String),

    /// Failed to unstage file.
    #[error("Failed to unstage file '{0}': {1}")]
    UnstageFile(String, String),

    /// Failed to discard changes.
    #[error("Failed to discard changes: {0}")]
    DiscardChanges(String),

    /// Failed to create worktree.
    #[error("Failed to create worktree: {0}")]
    WorktreeCreate(String),

    /// Failed to remove worktree.
    #[error("Failed to remove worktree: {0}")]
    WorktreeRemove(String),

    /// Worktree already exists.
    #[error("Worktree already exists: {0}")]
    WorktreeExists(String),

    /// Invalid path.
    #[error("Invalid path: {0}")]
    InvalidPath(String),

    /// Filesystem operation failed.
    #[error("Filesystem error: {0}")]
    Filesystem(String),
}

impl PiccoloError {
    /// Converts the error to a simple string message.
    ///
    /// This is provided for backward compatibility with the existing
    /// API that returns `Result<T, String>`.
    pub fn to_error_string(&self) -> String {
        self.to_string()
    }
}

impl From<PiccoloError> for String {
    fn from(err: PiccoloError) -> Self {
        err.to_string()
    }
}
