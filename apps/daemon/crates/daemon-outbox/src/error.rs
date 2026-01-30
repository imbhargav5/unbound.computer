//! Outbox error types.

use thiserror::Error;

/// Outbox error type.
#[derive(Error, Debug)]
pub enum OutboxError {
    /// Database error
    #[error("Database error: {0}")]
    Database(#[from] daemon_database::DatabaseError),

    /// HTTP request error
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    /// Send error
    #[error("Send failed: {0}")]
    Send(String),

    /// Queue error
    #[error("Queue error: {0}")]
    Queue(String),

    /// Session not found
    #[error("Session not found: {0}")]
    SessionNotFound(String),

    /// Max retries exceeded
    #[error("Max retries exceeded for batch {0}")]
    MaxRetriesExceeded(String),

    /// JSON error
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Result type alias using OutboxError.
pub type OutboxResult<T> = Result<T, OutboxError>;
