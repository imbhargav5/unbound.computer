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

    /// Failed to create commit.
    #[error("Failed to create commit: {0}")]
    CommitCreation(String),

    /// No staged changes to commit.
    #[error("Nothing to commit: no staged changes")]
    NothingToCommit,

    /// Push operation failed.
    #[error("Push failed: {0}")]
    PushFailed(String),

    /// No commits to push.
    #[error("Nothing to push: branch is up to date with remote")]
    NothingToPush,

    /// Authentication required for remote operation.
    #[error("Authentication required for remote: {0}")]
    AuthRequired(String),

    /// Remote not found.
    #[error("Remote not found: {0}")]
    RemoteNotFound(String),

    /// Invalid path.
    #[error("Invalid path: {0}")]
    InvalidPath(String),

    /// Filesystem operation failed.
    #[error("Filesystem error: {0}")]
    Filesystem(String),
}

impl From<git2::Error> for PiccoloError {
    fn from(err: git2::Error) -> Self {
        match err.class() {
            git2::ErrorClass::Repository => PiccoloError::RepositoryOpen(err.message().to_string()),
            git2::ErrorClass::Index => PiccoloError::IndexAccess(err.message().to_string()),
            git2::ErrorClass::Reference => PiccoloError::HeadAccess(err.message().to_string()),
            git2::ErrorClass::Net | git2::ErrorClass::Http | git2::ErrorClass::Ssh => {
                PiccoloError::AuthRequired(err.message().to_string())
            }
            _ => PiccoloError::CommitCreation(err.message().to_string()),
        }
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_messages_for_all_variants() {
        let cases: Vec<(PiccoloError, &str)> = vec![
            (
                PiccoloError::RepositoryOpen("not found".into()),
                "Failed to open repository: not found",
            ),
            (
                PiccoloError::HeadAccess("detached".into()),
                "Failed to get HEAD: detached",
            ),
            (
                PiccoloError::IndexAccess("locked".into()),
                "Failed to access index: locked",
            ),
            (
                PiccoloError::IndexWrite("permission".into()),
                "Failed to write index: permission",
            ),
            (
                PiccoloError::StatusQuery("timeout".into()),
                "Failed to get status: timeout",
            ),
            (
                PiccoloError::DiffGeneration("corrupt".into()),
                "Failed to generate diff: corrupt",
            ),
            (
                PiccoloError::BranchNotFound("feature".into()),
                "Branch not found: feature",
            ),
            (
                PiccoloError::BranchList("io error".into()),
                "Failed to list branches: io error",
            ),
            (
                PiccoloError::BranchCreate("exists".into()),
                "Failed to create branch: exists",
            ),
            (
                PiccoloError::RevwalkCreate("memory".into()),
                "Failed to create revision walker: memory",
            ),
            (
                PiccoloError::StageFile("main.rs".into(), "not found".into()),
                "Failed to stage file 'main.rs': not found",
            ),
            (
                PiccoloError::UnstageFile("lib.rs".into(), "locked".into()),
                "Failed to unstage file 'lib.rs': locked",
            ),
            (
                PiccoloError::DiscardChanges("checkout failed".into()),
                "Failed to discard changes: checkout failed",
            ),
            (
                PiccoloError::WorktreeCreate("dir exists".into()),
                "Failed to create worktree: dir exists",
            ),
            (
                PiccoloError::WorktreeRemove("in use".into()),
                "Failed to remove worktree: in use",
            ),
            (
                PiccoloError::WorktreeExists("session-1".into()),
                "Worktree already exists: session-1",
            ),
            (
                PiccoloError::CommitCreation("tree empty".into()),
                "Failed to create commit: tree empty",
            ),
            (
                PiccoloError::NothingToCommit,
                "Nothing to commit: no staged changes",
            ),
            (
                PiccoloError::PushFailed("rejected".into()),
                "Push failed: rejected",
            ),
            (
                PiccoloError::NothingToPush,
                "Nothing to push: branch is up to date with remote",
            ),
            (
                PiccoloError::AuthRequired("origin".into()),
                "Authentication required for remote: origin",
            ),
            (
                PiccoloError::RemoteNotFound("upstream".into()),
                "Remote not found: upstream",
            ),
            (PiccoloError::InvalidPath("..".into()), "Invalid path: .."),
            (
                PiccoloError::Filesystem("read only".into()),
                "Filesystem error: read only",
            ),
        ];

        for (error, expected) in cases {
            assert_eq!(
                error.to_string(),
                expected,
                "Display for {:?} should be \"{}\"",
                error,
                expected
            );
        }
    }

    #[test]
    fn to_error_string_matches_display() {
        let err = PiccoloError::RepositoryOpen("test".into());
        assert_eq!(err.to_error_string(), err.to_string());
    }

    #[test]
    fn into_string_conversion() {
        let err = PiccoloError::BranchNotFound("main".into());
        let s: String = err.into();
        assert_eq!(s, "Branch not found: main");
    }

    #[test]
    fn debug_format_contains_variant_name() {
        let err = PiccoloError::WorktreeCreate("test".into());
        let debug = format!("{:?}", err);
        assert!(
            debug.contains("WorktreeCreate"),
            "Debug output should contain variant name, got: {}",
            debug
        );
    }
}
