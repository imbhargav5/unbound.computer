//! Error types for Session sync Supabase sync operations.
//!
//! Defines error variants for network, API, serialization, and configuration
//! failures that can occur during sync operations.

use thiserror::Error;

/// Comprehensive error type for all Session sync operations.
///
/// Uses thiserror for automatic Display and Error trait implementations.
/// Supports automatic conversion from reqwest and serde_json errors via #[from].
#[derive(Debug, Error)]
pub enum SessionSyncError {
    /// Network or transport-level HTTP error from reqwest.
    ///
    /// Includes connection failures, timeouts, and TLS errors.
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    /// Supabase API returned a non-success HTTP status.
    ///
    /// Contains the HTTP status code and response body for debugging.
    /// Common causes: authentication failure, RLS policy violation, schema mismatch.
    #[error("Supabase error: {status} - {message}")]
    Supabase {
        /// The HTTP status code returned by Supabase.
        status: u16,
        /// The response body, typically containing error details.
        message: String,
    },

    /// JSON serialization or deserialization failed.
    ///
    /// Occurs when request bodies cannot be serialized or responses
    /// don't match expected schema.
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// Configuration or initialization error.
    ///
    /// Used for invalid API URLs, missing credentials, or other setup issues.
    #[error("Configuration error: {0}")]
    Config(String),
}

/// Convenience Result type alias for Session sync operations.
///
/// Reduces boilerplate by pre-specifying SessionSyncError as the error type.
pub type SessionSyncResult<T> = Result<T, SessionSyncError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn supabase_error_display() {
        let err = SessionSyncError::Supabase {
            status: 401,
            message: "JWT expired".to_string(),
        };
        let display = format!("{}", err);
        assert_eq!(display, "Supabase error: 401 - JWT expired");
    }

    #[test]
    fn config_error_display() {
        let err = SessionSyncError::Config("missing API URL".to_string());
        let display = format!("{}", err);
        assert_eq!(display, "Configuration error: missing API URL");
    }

    #[test]
    fn json_error_from_serde() {
        let bad_json = "not json at all {{{";
        let serde_err = serde_json::from_str::<serde_json::Value>(bad_json).unwrap_err();
        let err: SessionSyncError = serde_err.into();
        let display = format!("{}", err);
        assert!(display.starts_with("JSON error:"));
    }

    #[test]
    fn supabase_error_is_debug() {
        let err = SessionSyncError::Supabase {
            status: 500,
            message: "internal".to_string(),
        };
        let debug = format!("{:?}", err);
        assert!(debug.contains("500"));
        assert!(debug.contains("internal"));
    }
}
