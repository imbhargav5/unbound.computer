//! Relay error types.

use thiserror::Error;

/// Relay error type.
#[derive(Error, Debug)]
pub enum RelayError {
    /// WebSocket error
    #[error("WebSocket error: {0}")]
    WebSocket(#[from] tokio_tungstenite::tungstenite::Error),

    /// Connection error
    #[error("Connection error: {0}")]
    Connection(String),

    /// Authentication error
    #[error("Authentication failed: {0}")]
    Authentication(String),

    /// Not connected error
    #[error("Not connected to relay")]
    NotConnected,

    /// Session error
    #[error("Session error: {0}")]
    Session(String),

    /// JSON serialization error
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Timeout error
    #[error("Operation timed out")]
    Timeout,

    /// Send error
    #[error("Failed to send message: {0}")]
    Send(String),
}

/// Result type alias using RelayError.
pub type RelayResult<T> = Result<T, RelayError>;
