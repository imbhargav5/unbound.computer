//! Error types for ClaudeProcess.

use thiserror::Error;

/// ClaudeProcess error type.
#[derive(Debug, Error)]
pub enum ClaudeProcessError {
    /// Failed to spawn the Claude process.
    #[error("Failed to spawn Claude process: {0}")]
    SpawnFailed(#[from] std::io::Error),

    /// Failed to get stdout from the process.
    #[error("Failed to get stdout from Claude process")]
    NoStdout,

    /// Process was killed.
    #[error("Claude process was killed")]
    Killed,

    /// JSON parsing error.
    #[error("JSON parsing error: {0}")]
    JsonParse(#[from] serde_json::Error),

    /// Configuration error.
    #[error("Configuration error: {0}")]
    Config(String),
}

/// Result type for ClaudeProcess operations.
pub type ClaudeProcessResult<T> = Result<T, ClaudeProcessError>;
