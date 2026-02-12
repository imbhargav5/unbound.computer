use thiserror::Error;

/// Error taxonomy for GitHub CLI orchestration.
#[derive(Debug, Error)]
pub enum BakugouError {
    #[error("GitHub CLI is not installed")]
    GhNotInstalled,

    #[error("GitHub CLI is not authenticated: {message}")]
    GhNotAuthenticated { message: String },

    #[error("Invalid repository context: {message}")]
    InvalidRepository { message: String },

    #[error("Invalid parameters: {message}")]
    InvalidParams { message: String },

    #[error("Resource not found: {message}")]
    NotFound { message: String },

    #[error("GitHub CLI command failed: {message}")]
    CommandFailed {
        message: String,
        exit_code: Option<i32>,
        stderr: String,
        stdout: String,
    },

    #[error("GitHub CLI command timed out after {timeout_secs}s: {command}")]
    Timeout {
        command: String,
        timeout_secs: u64,
    },

    #[error("Failed to parse GitHub CLI output: {message}")]
    ParseError { message: String },
}

impl BakugouError {
    /// Stable machine-readable error code for IPC and remote command clients.
    pub fn code(&self) -> &'static str {
        match self {
            Self::GhNotInstalled => "gh_not_installed",
            Self::GhNotAuthenticated { .. } => "gh_not_authenticated",
            Self::InvalidRepository { .. } => "invalid_repository",
            Self::InvalidParams { .. } => "invalid_params",
            Self::NotFound { .. } => "not_found",
            Self::CommandFailed { .. } => "command_failed",
            Self::Timeout { .. } => "timeout",
            Self::ParseError { .. } => "parse_error",
        }
    }
}
