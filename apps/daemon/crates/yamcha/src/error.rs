//! Error types for the yamcha session title generator.

use thiserror::Error;

/// Errors that can occur during session title generation.
#[derive(Error, Debug)]
pub enum YamchaError {
    /// HTTP request failed
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    /// JSON serialization/deserialization error
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// API returned an error response
    #[error("Groq API error: {status} - {message}")]
    ApiError { status: u16, message: String },

    /// Missing API key
    #[error("Missing Groq API key")]
    MissingApiKey,

    /// Invalid response from API (missing expected fields)
    #[error("Invalid API response: {0}")]
    InvalidResponse(String),
}

/// Result type alias using YamchaError.
pub type YamchaResult<T> = Result<T, YamchaError>;
