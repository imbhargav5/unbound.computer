//! Core error types for the daemon.

use thiserror::Error;

/// Core error type for daemon operations.
#[derive(Error, Debug)]
pub enum CoreError {
    /// Configuration error
    #[error("Configuration error: {0}")]
    Config(String),

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// URL parsing error
    #[error("Invalid URL: {0}")]
    InvalidUrl(#[from] url::ParseError),

    /// JSON serialization/deserialization error
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// Path error (e.g., home directory not found)
    #[error("Path error: {0}")]
    Path(String),

    /// Cryptographic error
    #[error("Crypto error: {0}")]
    Crypto(String),
}

/// Result type alias using CoreError.
pub type CoreResult<T> = Result<T, CoreError>;
