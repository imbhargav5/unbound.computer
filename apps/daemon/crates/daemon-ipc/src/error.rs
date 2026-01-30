//! IPC error types.

use thiserror::Error;

/// IPC error type.
#[derive(Error, Debug)]
pub enum IpcError {
    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// JSON error
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// Protocol error
    #[error("Protocol error: {0}")]
    Protocol(String),

    /// Method not found
    #[error("Method not found: {0}")]
    MethodNotFound(String),

    /// Invalid parameters
    #[error("Invalid parameters: {0}")]
    InvalidParams(String),

    /// Internal error
    #[error("Internal error: {0}")]
    Internal(String),

    /// Socket error
    #[error("Socket error: {0}")]
    Socket(String),

    /// Connection closed
    #[error("Connection closed")]
    ConnectionClosed,
}

/// Result type alias using IpcError.
pub type IpcResult<T> = Result<T, IpcError>;
