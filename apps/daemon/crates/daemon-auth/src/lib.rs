//! Authentication module for the Unbound daemon.
//!
//! This crate provides:
//! - OAuth flow via local HTTP callback server
//! - Session management with automatic token refresh
//! - Integration with secure storage for token persistence
//! - Supabase REST client for device and session secret management
//! - Explicit FSM-based auth state management

mod auth_fsm;
mod error;
mod oauth;
mod session;
mod supabase_client;

pub use auth_fsm::{
    AuthMachine, AuthMachineInput, AuthMachineState, AuthState, AuthStateChangedPayload,
    RefreshConfig,
};
pub use auth_fsm::auth_machine;
pub use error::{AuthError, AuthResult};
pub use oauth::{OAuthCallbackServer, OAuthResult};
pub use session::{AuthStatus, SessionManager};
pub use supabase_client::{CodingSessionSecretRecord, DeviceInfo, SupabaseClient};
