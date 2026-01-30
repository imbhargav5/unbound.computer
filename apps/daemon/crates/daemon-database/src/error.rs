//! Database error types.

use thiserror::Error;

/// Database error type.
#[derive(Error, Debug)]
pub enum DatabaseError {
    /// SQLite error
    #[error("SQLite error: {0}")]
    Sqlite(#[from] rusqlite::Error),

    /// Connection pool error
    #[error("Connection error: {0}")]
    Connection(String),

    /// Migration error
    #[error("Migration error: {0}")]
    Migration(String),

    /// Encryption error
    #[error("Encryption error: {0}")]
    Encryption(String),

    /// Not found error
    #[error("Not found: {0}")]
    NotFound(String),

    /// JSON serialization error
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Invalid data error
    #[error("Invalid data: {0}")]
    InvalidData(String),
}

/// Result type alias using DatabaseError.
pub type DatabaseResult<T> = Result<T, DatabaseError>;
