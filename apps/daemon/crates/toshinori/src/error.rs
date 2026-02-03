//! Error types for Toshinori.

use thiserror::Error;

/// Toshinori error type.
#[derive(Debug, Error)]
pub enum ToshinoriError {
    /// HTTP request failed.
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    /// Supabase API returned an error.
    #[error("Supabase error: {status} - {message}")]
    Supabase { status: u16, message: String },

    /// JSON serialization error.
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// Configuration error.
    #[error("Configuration error: {0}")]
    Config(String),
}

/// Result type for Toshinori operations.
pub type ToshinoriResult<T> = Result<T, ToshinoriError>;
