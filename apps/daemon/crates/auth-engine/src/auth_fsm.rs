//! Authentication state machine using rust-fsm.
//!
//! This module defines an explicit finite state machine for authentication,
//! replacing implicit state derivation from storage checks.
//!
//! ## State Diagram
//!
//! ```text
//! ┌─────────────────┐
//! │   NotLoggedIn   │ (initial)
//! └────────┬────────┘
//!          │ LoginAttempt / ValidateSession
//!          ▼
//! ┌─────────────────┐     ┌─────────────────┐
//! │   LoggingIn     │     │   Validating    │
//! └────────┬────────┘     └────────┬────────┘
//!          │                       │
//!          │ LoginSuccess          │ TokenNotExpired ──► VerifyingWithServer
//!          │                       │                            │
//!          │                       │ SessionExpired             │ ServerVerified/ServerRejected
//!          │                       │                            │
//!          │                       │ NoSession                  ▼
//!          ▼                       ▼                     LoggedIn/NotLoggedIn
//! ┌─────────────────┐      TokenExpired      ┌─────────────────┐
//! │    LoggedIn     │ ─────────────────────► │   Refreshing    │
//! └────────┬────────┘                        └────────┬────────┘
//!          │                                          │
//!          │ LogoutRequested                          │ RefreshSuccess/RefreshFailed
//!          ▼                                          ▼
//! ┌─────────────────┐                        ┌─────────────────┐
//! │  LoggingOut     │                        │  (Back to       │
//! └────────┬────────┘                        │   appropriate)  │
//!          │ LogoutComplete                  └─────────────────┘
//!          ▼
//!     NotLoggedIn
//! ```

use rust_fsm::*;
use serde::{Deserialize, Serialize};
use std::time::Duration;

// Define the FSM using rust-fsm's declarative macro
// This generates a module `auth_machine` with:
// - auth_machine::State (enum)
// - auth_machine::Input (enum)
// - auth_machine::StateMachine (type alias)
// - auth_machine::Impl (trait impl)
state_machine! {
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub auth_machine(NotLoggedIn)

    NotLoggedIn => {
        SessionDetected => PendingValidation,
        LoginAttempt => LoggingIn,
        ValidateSession => Validating
    },
    PendingValidation => {
        ValidateSession => Validating,
        LoginAttempt => LoggingIn,
        NoSession => NotLoggedIn
    },
    Validating => {
        // Token not expired locally - must verify with server
        TokenNotExpired => VerifyingWithServer,
        // Token expired locally - attempt refresh
        SessionExpired => Refreshing,
        // No session exists
        NoSession => NotLoggedIn
    },
    VerifyingWithServer => {
        // Server confirmed session is valid
        ServerVerified => LoggedIn,
        // Server rejected session (revoked, invalid, etc.)
        ServerRejected => NotLoggedIn
    },
    LoggingIn => {
        LoginSuccess => LoggedIn,
        LoginFailed => NotLoggedIn
    },
    LoggedIn => {
        TokenExpired => Refreshing,
        LogoutRequested => LoggingOut
    },
    Refreshing => {
        RefreshSuccess => LoggedIn,
        RefreshRetry => Refreshing,
        RefreshFailed => NotLoggedIn
    },
    LoggingOut => {
        LogoutComplete => NotLoggedIn
    }
}

// Re-export the generated types with clearer names
pub use auth_machine::Input as AuthMachineInput;
pub use auth_machine::State as AuthMachineState;
pub use auth_machine::StateMachine as AuthMachine;

/// User-friendly authentication state for external consumption.
///
/// This is a simplified view of the FSM state for IPC and UI purposes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AuthState {
    /// Not logged in.
    NotLoggedIn,
    /// Stored credentials exist but have not yet been validated.
    PendingValidation,
    /// Currently logging in.
    LoggingIn,
    /// Validating existing session (checking local storage).
    Validating,
    /// Verifying session with Supabase server.
    VerifyingWithServer,
    /// Logged in with valid session.
    LoggedIn,
    /// Refreshing expired token.
    Refreshing,
    /// Currently logging out.
    LoggingOut,
}

impl AuthState {
    /// Returns true if the user has a valid session (LoggedIn state only).
    pub fn is_authenticated(&self) -> bool {
        matches!(self, AuthState::LoggedIn)
    }

    /// Returns true if the state is a transient/in-progress state.
    pub fn is_transient(&self) -> bool {
        matches!(
            self,
            AuthState::PendingValidation
                | AuthState::LoggingIn
                | AuthState::Validating
                | AuthState::VerifyingWithServer
                | AuthState::Refreshing
                | AuthState::LoggingOut
        )
    }
}

impl From<&AuthMachineState> for AuthState {
    fn from(state: &AuthMachineState) -> Self {
        match state {
            AuthMachineState::NotLoggedIn => AuthState::NotLoggedIn,
            AuthMachineState::PendingValidation => AuthState::PendingValidation,
            AuthMachineState::LoggingIn => AuthState::LoggingIn,
            AuthMachineState::Validating => AuthState::Validating,
            AuthMachineState::VerifyingWithServer => AuthState::VerifyingWithServer,
            AuthMachineState::LoggedIn => AuthState::LoggedIn,
            AuthMachineState::Refreshing => AuthState::Refreshing,
            AuthMachineState::LoggingOut => AuthState::LoggingOut,
        }
    }
}

/// Configuration for retry behavior during token refresh.
#[derive(Debug, Clone)]
pub struct RefreshConfig {
    /// Maximum number of retry attempts.
    pub max_retries: u32,
    /// Initial delay between retries in milliseconds.
    pub initial_delay_ms: u64,
    /// Maximum delay between retries in milliseconds.
    pub max_delay_ms: u64,
}

impl Default for RefreshConfig {
    fn default() -> Self {
        Self {
            max_retries: 3,
            initial_delay_ms: 500,
            max_delay_ms: 5000,
        }
    }
}

impl RefreshConfig {
    /// Calculate the delay for a given attempt number (0-indexed).
    pub fn delay_for_attempt(&self, attempt: u32) -> Duration {
        let delay_ms = self.initial_delay_ms.saturating_mul(2u64.pow(attempt));
        let capped_ms = delay_ms.min(self.max_delay_ms);
        Duration::from_millis(capped_ms)
    }
}

/// Payload for auth state change events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthStateChangedPayload {
    /// Current auth state.
    pub state: AuthState,
    /// User ID if logged in.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_id: Option<String>,
    /// User email if available.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initial_state_is_not_logged_in() {
        let machine = AuthMachine::new();
        assert_eq!(*machine.state(), AuthMachineState::NotLoggedIn);
    }

    #[test]
    fn test_login_flow() {
        let mut machine = AuthMachine::new();

        // Start login
        let result = machine.consume(&AuthMachineInput::LoginAttempt);
        assert!(result.is_ok());
        assert_eq!(*machine.state(), AuthMachineState::LoggingIn);

        // Login succeeds
        let result = machine.consume(&AuthMachineInput::LoginSuccess);
        assert!(result.is_ok());
        assert_eq!(*machine.state(), AuthMachineState::LoggedIn);
    }

    #[test]
    fn test_session_detected_transitions_to_pending_validation() {
        let mut machine = AuthMachine::new();

        machine.consume(&AuthMachineInput::SessionDetected).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::PendingValidation);
    }

    #[test]
    fn test_login_failure_returns_to_not_logged_in() {
        let mut machine = AuthMachine::new();

        // Start login
        machine.consume(&AuthMachineInput::LoginAttempt).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::LoggingIn);

        // Login fails
        let result = machine.consume(&AuthMachineInput::LoginFailed);
        assert!(result.is_ok());
        assert_eq!(*machine.state(), AuthMachineState::NotLoggedIn);
    }

    #[test]
    fn test_validate_session_flow_server_verified() {
        let mut machine = AuthMachine::new();

        // Start validation
        machine.consume(&AuthMachineInput::ValidateSession).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Validating);

        // Token not expired - must verify with server
        machine.consume(&AuthMachineInput::TokenNotExpired).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::VerifyingWithServer);

        // Server verifies session is valid
        machine.consume(&AuthMachineInput::ServerVerified).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::LoggedIn);
    }

    #[test]
    fn test_validate_session_flow_server_rejected() {
        let mut machine = AuthMachine::new();

        // Start validation
        machine.consume(&AuthMachineInput::ValidateSession).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Validating);

        // Token not expired - must verify with server
        machine.consume(&AuthMachineInput::TokenNotExpired).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::VerifyingWithServer);

        // Server rejects session (revoked, invalid, etc.)
        machine.consume(&AuthMachineInput::ServerRejected).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::NotLoggedIn);
    }

    #[test]
    fn test_cannot_skip_server_verification() {
        let mut machine = AuthMachine::new();

        // Start validation
        machine.consume(&AuthMachineInput::ValidateSession).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Validating);

        // Cannot go directly to LoggedIn from Validating (must go through VerifyingWithServer)
        let result = machine.consume(&AuthMachineInput::ServerVerified);
        assert!(result.is_err());

        // Token not expired - must verify with server first
        machine.consume(&AuthMachineInput::TokenNotExpired).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::VerifyingWithServer);

        // Now server verification succeeds
        machine.consume(&AuthMachineInput::ServerVerified).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::LoggedIn);
    }

    #[test]
    fn test_validate_session_flow_expired() {
        let mut machine = AuthMachine::new();

        // Start validation
        machine.consume(&AuthMachineInput::ValidateSession).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Validating);

        // Session is expired - goes to refreshing
        machine.consume(&AuthMachineInput::SessionExpired).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Refreshing);

        // Refresh succeeds
        machine.consume(&AuthMachineInput::RefreshSuccess).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::LoggedIn);
    }

    #[test]
    fn test_validate_session_flow_no_session() {
        let mut machine = AuthMachine::new();

        // Start validation
        machine.consume(&AuthMachineInput::ValidateSession).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Validating);

        // No session exists
        machine.consume(&AuthMachineInput::NoSession).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::NotLoggedIn);
    }

    #[test]
    fn test_token_expired_triggers_refresh() {
        let mut machine = AuthMachine::new();

        // Get to logged in state
        machine.consume(&AuthMachineInput::LoginAttempt).unwrap();
        machine.consume(&AuthMachineInput::LoginSuccess).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::LoggedIn);

        // Token expires
        machine.consume(&AuthMachineInput::TokenExpired).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Refreshing);
    }

    #[test]
    fn test_refresh_retry() {
        let mut machine = AuthMachine::new();

        // Get to refreshing state
        machine.consume(&AuthMachineInput::LoginAttempt).unwrap();
        machine.consume(&AuthMachineInput::LoginSuccess).unwrap();
        machine.consume(&AuthMachineInput::TokenExpired).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Refreshing);

        // Retry stays in refreshing
        machine.consume(&AuthMachineInput::RefreshRetry).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Refreshing);

        // Retry again
        machine.consume(&AuthMachineInput::RefreshRetry).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Refreshing);

        // Finally succeeds
        machine.consume(&AuthMachineInput::RefreshSuccess).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::LoggedIn);
    }

    #[test]
    fn test_refresh_failure_clears_session() {
        let mut machine = AuthMachine::new();

        // Get to refreshing state
        machine.consume(&AuthMachineInput::LoginAttempt).unwrap();
        machine.consume(&AuthMachineInput::LoginSuccess).unwrap();
        machine.consume(&AuthMachineInput::TokenExpired).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::Refreshing);

        // Refresh fails
        machine.consume(&AuthMachineInput::RefreshFailed).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::NotLoggedIn);
    }

    #[test]
    fn test_logout_flow() {
        let mut machine = AuthMachine::new();

        // Get to logged in state
        machine.consume(&AuthMachineInput::LoginAttempt).unwrap();
        machine.consume(&AuthMachineInput::LoginSuccess).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::LoggedIn);

        // Request logout
        machine.consume(&AuthMachineInput::LogoutRequested).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::LoggingOut);

        // Logout completes
        machine.consume(&AuthMachineInput::LogoutComplete).unwrap();
        assert_eq!(*machine.state(), AuthMachineState::NotLoggedIn);
    }

    #[test]
    fn test_invalid_transition_returns_error() {
        let mut machine = AuthMachine::new();

        // Can't logout from NotLoggedIn
        let result = machine.consume(&AuthMachineInput::LogoutRequested);
        assert!(result.is_err());

        // Can't claim LoginSuccess from NotLoggedIn
        let result = machine.consume(&AuthMachineInput::LoginSuccess);
        assert!(result.is_err());
    }

    #[test]
    fn test_auth_state_conversion() {
        assert_eq!(
            AuthState::from(&AuthMachineState::NotLoggedIn),
            AuthState::NotLoggedIn
        );
        assert_eq!(
            AuthState::from(&AuthMachineState::PendingValidation),
            AuthState::PendingValidation
        );
        assert_eq!(
            AuthState::from(&AuthMachineState::LoggingIn),
            AuthState::LoggingIn
        );
        assert_eq!(
            AuthState::from(&AuthMachineState::Validating),
            AuthState::Validating
        );
        assert_eq!(
            AuthState::from(&AuthMachineState::VerifyingWithServer),
            AuthState::VerifyingWithServer
        );
        assert_eq!(
            AuthState::from(&AuthMachineState::LoggedIn),
            AuthState::LoggedIn
        );
        assert_eq!(
            AuthState::from(&AuthMachineState::Refreshing),
            AuthState::Refreshing
        );
        assert_eq!(
            AuthState::from(&AuthMachineState::LoggingOut),
            AuthState::LoggingOut
        );
    }

    #[test]
    fn test_auth_state_is_authenticated() {
        assert!(!AuthState::NotLoggedIn.is_authenticated());
        assert!(!AuthState::PendingValidation.is_authenticated());
        assert!(!AuthState::LoggingIn.is_authenticated());
        assert!(!AuthState::Validating.is_authenticated());
        assert!(!AuthState::VerifyingWithServer.is_authenticated());
        assert!(AuthState::LoggedIn.is_authenticated());
        assert!(!AuthState::Refreshing.is_authenticated());
        assert!(!AuthState::LoggingOut.is_authenticated());
    }

    #[test]
    fn test_auth_state_is_transient() {
        assert!(!AuthState::NotLoggedIn.is_transient());
        assert!(AuthState::PendingValidation.is_transient());
        assert!(AuthState::LoggingIn.is_transient());
        assert!(AuthState::Validating.is_transient());
        assert!(AuthState::VerifyingWithServer.is_transient());
        assert!(!AuthState::LoggedIn.is_transient());
        assert!(AuthState::Refreshing.is_transient());
        assert!(AuthState::LoggingOut.is_transient());
    }

    #[test]
    fn test_refresh_config_default() {
        let config = RefreshConfig::default();
        assert_eq!(config.max_retries, 3);
        assert_eq!(config.initial_delay_ms, 500);
        assert_eq!(config.max_delay_ms, 5000);
    }

    #[test]
    fn test_refresh_config_delay_exponential_backoff() {
        let config = RefreshConfig::default();

        // Attempt 0: 500ms
        assert_eq!(config.delay_for_attempt(0), Duration::from_millis(500));

        // Attempt 1: 1000ms
        assert_eq!(config.delay_for_attempt(1), Duration::from_millis(1000));

        // Attempt 2: 2000ms
        assert_eq!(config.delay_for_attempt(2), Duration::from_millis(2000));

        // Attempt 3: 4000ms
        assert_eq!(config.delay_for_attempt(3), Duration::from_millis(4000));

        // Attempt 4: 5000ms (capped)
        assert_eq!(config.delay_for_attempt(4), Duration::from_millis(5000));

        // Attempt 5: still 5000ms (capped)
        assert_eq!(config.delay_for_attempt(5), Duration::from_millis(5000));
    }
}
