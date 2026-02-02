//! Error types for Falco.

use thiserror::Error;

/// Falco error type.
#[derive(Error, Debug)]
pub enum FalcoError {
    /// Redis connection or operation error
    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    /// IO error (socket, file operations)
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Protocol error (invalid frames, unexpected data)
    #[error("Protocol error: {0}")]
    Protocol(String),

    /// Configuration error
    #[error("Configuration error: {0}")]
    Config(String),

    /// Daemon connection error
    #[error("Daemon connection error: {0}")]
    DaemonConnection(String),

    /// Timeout waiting for daemon response
    #[error("Timeout waiting for daemon response after {0} seconds")]
    Timeout(u64),

    /// Storage error (device ID retrieval)
    #[error("Storage error: {0}")]
    Storage(#[from] daemon_storage::StorageError),

    /// UUID parsing error
    #[error("UUID error: {0}")]
    Uuid(#[from] uuid::Error),
}

/// Result type for Falco operations.
pub type FalcoResult<T> = Result<T, FalcoError>;
