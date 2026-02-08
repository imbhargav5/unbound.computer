//! Authentication error types.

use thiserror::Error;

/// Authentication error type.
#[derive(Error, Debug)]
pub enum AuthError {
    /// Invalid email or password
    #[error("Invalid credentials: {0}")]
    InvalidCredentials(String),

    /// OAuth flow error (used by Supabase client)
    #[error("OAuth error: {0}")]
    OAuth(String),

    /// Token refresh error
    #[error("Token refresh failed: {0}")]
    TokenRefresh(String),

    /// Refresh retries exhausted
    #[error("Token refresh failed after {0} attempts")]
    RefreshExhausted(u32),

    /// Session not found
    #[error("Not logged in")]
    NotLoggedIn,

    /// Session expired and refresh failed
    #[error("Session expired")]
    SessionExpired,

    /// Session was invalidated server-side (revoked, logged out elsewhere, etc.)
    #[error("Session invalid: {0}")]
    SessionInvalid(String),

    /// Invalid state transition in the auth FSM
    #[error("Invalid auth state transition: {0}")]
    InvalidStateTransition(String),

    /// Storage error
    #[error("Storage error: {0}")]
    Storage(#[from] daemon_storage::StorageError),

    /// HTTP request error
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// JSON error
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// URL parse error
    #[error("Invalid URL: {0}")]
    InvalidUrl(#[from] url::ParseError),

    /// Timeout error
    #[error("Operation timed out")]
    Timeout,

    /// Network unavailable (transient error, can retry)
    #[error("Network unavailable")]
    NetworkUnavailable,

    /// Configuration error
    #[error("Configuration error: {0}")]
    Config(String),
}

impl AuthError {
    /// Returns true if this error is transient and the operation can be retried.
    ///
    /// Transient errors include:
    /// - Network unavailable
    /// - HTTP errors with 5xx status codes
    /// - Connection timeouts
    pub fn is_transient(&self) -> bool {
        match self {
            AuthError::NetworkUnavailable => true,
            AuthError::Timeout => true,
            AuthError::Http(e) => {
                // Check if it's a connection error or 5xx server error
                if e.is_connect() || e.is_timeout() {
                    return true;
                }
                if let Some(status) = e.status() {
                    return status.is_server_error();
                }
                false
            }
            _ => false,
        }
    }
}

/// Result type alias using AuthError.
pub type AuthResult<T> = Result<T, AuthError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_transient_network_unavailable() {
        assert!(AuthError::NetworkUnavailable.is_transient());
    }

    #[test]
    fn test_is_transient_timeout() {
        assert!(AuthError::Timeout.is_transient());
    }

    #[test]
    fn test_is_not_transient_invalid_credentials() {
        assert!(!AuthError::InvalidCredentials("bad password".to_string()).is_transient());
    }

    #[test]
    fn test_is_not_transient_not_logged_in() {
        assert!(!AuthError::NotLoggedIn.is_transient());
    }

    #[test]
    fn test_is_not_transient_session_expired() {
        assert!(!AuthError::SessionExpired.is_transient());
    }

    #[test]
    fn test_is_not_transient_refresh_exhausted() {
        assert!(!AuthError::RefreshExhausted(3).is_transient());
    }

    #[test]
    fn test_is_not_transient_session_invalid() {
        assert!(!AuthError::SessionInvalid("revoked".to_string()).is_transient());
    }
}
