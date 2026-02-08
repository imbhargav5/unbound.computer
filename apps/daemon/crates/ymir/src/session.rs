//! Session management with automatic token refresh using FSM-based state management.
//!
//! This module provides a `SessionManager` that uses an internal finite state machine
//! to track authentication state explicitly, rather than deriving it from storage.
//! This provides better reliability, testability, and observability.

use crate::auth_fsm::{
    AuthMachine, AuthMachineInput, AuthState, AuthStateChangedPayload, RefreshConfig,
};
use crate::{AuthError, AuthResult};
use chrono::{Duration, Utc};
use daemon_storage::{SecretsManager, SupabaseSessionMeta};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tracing::{debug, info, warn};

/// Authentication status (backward-compatible public API).
#[derive(Debug, Clone)]
pub enum AuthStatus {
    /// Logged in with valid session.
    LoggedIn { user_id: String, expires_at: String },
    /// Not logged in.
    NotLoggedIn,
    /// Session expired and refresh failed.
    Expired,
}

/// Supabase token refresh request.
#[derive(Debug, Serialize)]
struct RefreshRequest {
    refresh_token: String,
}

/// Supabase token refresh response.
#[derive(Debug, Deserialize)]
struct RefreshResponse {
    access_token: String,
    refresh_token: String,
    expires_in: i64,
    user: RefreshUser,
}

#[derive(Debug, Deserialize)]
struct RefreshUser {
    id: String,
    #[serde(default)]
    email: Option<String>,
}

/// Supabase user verification response.
#[derive(Debug, Deserialize)]
struct UserResponse {
    id: String,
    #[serde(default)]
    email: Option<String>,
}

/// Callback type for auth state change notifications.
pub type AuthStateCallback = Box<dyn Fn(AuthStateChangedPayload) + Send + Sync>;

/// Session manager for authentication state with FSM-based state tracking.
///
/// The FSM tracks transient states (logging in, refreshing, logging out) that
/// aren't persisted, while the actual session data (tokens) is stored in secure
/// storage. On startup, the FSM state is derived from storage for crash resilience.
pub struct SessionManager {
    secrets: SecretsManager,
    supabase_url: String,
    supabase_publishable_key: String,
    http_client: Client,
    /// Internal FSM for tracking auth state transitions.
    fsm: Mutex<AuthMachine>,
    /// Configuration for refresh retry behavior.
    refresh_config: RefreshConfig,
    /// Optional callback for state change notifications.
    state_callback: Mutex<Option<AuthStateCallback>>,
}

impl SessionManager {
    /// Create a new session manager.
    pub fn new(
        secrets: SecretsManager,
        supabase_url: &str,
        supabase_publishable_key: &str,
    ) -> Self {
        Self {
            secrets,
            supabase_url: supabase_url.to_string(),
            supabase_publishable_key: supabase_publishable_key.to_string(),
            http_client: Client::new(),
            fsm: Mutex::new(AuthMachine::new()),
            refresh_config: RefreshConfig::default(),
            state_callback: Mutex::new(None),
        }
    }

    /// Create a new session manager with custom refresh configuration.
    pub fn with_refresh_config(
        secrets: SecretsManager,
        supabase_url: &str,
        supabase_publishable_key: &str,
        refresh_config: RefreshConfig,
    ) -> Self {
        Self {
            secrets,
            supabase_url: supabase_url.to_string(),
            supabase_publishable_key: supabase_publishable_key.to_string(),
            http_client: Client::new(),
            fsm: Mutex::new(AuthMachine::new()),
            refresh_config,
            state_callback: Mutex::new(None),
        }
    }

    /// Set a callback to be notified of auth state changes.
    ///
    /// This is useful for broadcasting state changes via IPC.
    pub fn set_state_callback(&self, callback: AuthStateCallback) {
        let mut cb = self.state_callback.lock().unwrap();
        *cb = Some(callback);
    }

    /// Get the current FSM state.
    pub fn fsm_state(&self) -> AuthState {
        let fsm = self.fsm.lock().unwrap();
        AuthState::from(fsm.state())
    }

    /// Transition the FSM and notify callback if state changed.
    fn transition(&self, input: &AuthMachineInput) -> Result<AuthState, AuthError> {
        let mut fsm = self.fsm.lock().unwrap();
        let old_state = AuthState::from(fsm.state());

        fsm.consume(input).map_err(|_| {
            AuthError::InvalidStateTransition(format!(
                "Cannot apply {:?} in state {:?}",
                input,
                fsm.state()
            ))
        })?;

        let new_state = AuthState::from(fsm.state());
        drop(fsm);

        if old_state != new_state {
            debug!(
                old_state = ?old_state,
                new_state = ?new_state,
                "Auth state transition"
            );
            self.notify_state_change(&new_state);
        }

        Ok(new_state)
    }

    /// Notify the callback of a state change.
    fn notify_state_change(&self, state: &AuthState) {
        let cb = self.state_callback.lock().unwrap();
        if let Some(callback) = cb.as_ref() {
            let (user_id, email) = self
                .secrets
                .get_supabase_session_meta()
                .ok()
                .flatten()
                .map(|m| (Some(m.user_id), m.email))
                .unwrap_or((None, None));

            callback(AuthStateChangedPayload {
                state: state.clone(),
                user_id,
                email,
            });
        }
    }

    /// Validate and refresh session on startup.
    ///
    /// This should be called when the daemon starts to ensure the stored session
    /// is still valid. Always verifies the session with the Supabase server to
    /// ensure it hasn't been revoked. If the token is expired locally, attempts
    /// to refresh with exponential backoff. If refresh fails, the session is cleared.
    ///
    /// Uses the FSM to track state transitions:
    /// - NotLoggedIn -> Validating -> TokenNotExpired -> VerifyingWithServer -> ServerVerified -> LoggedIn
    /// - NotLoggedIn -> Validating -> TokenNotExpired -> VerifyingWithServer -> ServerRejected -> NotLoggedIn
    /// - NotLoggedIn -> Validating -> SessionExpired -> Refreshing -> RefreshSuccess -> LoggedIn
    /// - NotLoggedIn -> Validating -> NoSession -> NotLoggedIn
    ///
    /// Returns:
    /// - `Ok(true)` if session is valid or was successfully refreshed
    /// - `Ok(false)` if no session exists
    /// - `Err(...)` if session was invalid and has been cleared
    pub async fn validate_session_on_startup(&self) -> AuthResult<bool> {
        // Transition to validating state
        self.transition(&AuthMachineInput::ValidateSession)?;

        // Check if we have a session at all
        if !self.secrets.has_supabase_session()? {
            info!("No existing session found on startup");
            self.transition(&AuthMachineInput::NoSession)?;
            return Ok(false);
        }

        // Get session metadata
        let meta = match self.secrets.get_supabase_session_meta()? {
            Some(m) => m,
            None => {
                info!("Session tokens exist but metadata is missing, clearing session");
                self.secrets.clear_supabase_session()?;
                self.transition(&AuthMachineInput::NoSession)?;
                return Ok(false);
            }
        };

        // Get access token for server verification
        let access_token = match self.secrets.get_supabase_access_token()? {
            Some(t) => t,
            None => {
                info!("Session metadata exists but access token is missing, clearing session");
                self.secrets.clear_supabase_session()?;
                self.transition(&AuthMachineInput::NoSession)?;
                return Ok(false);
            }
        };

        // Check if token is expired locally first
        let token_expired = self.secrets.is_supabase_session_expired()?;

        if token_expired {
            // Token is expired locally - attempt refresh
            info!(
                user_id = %meta.user_id,
                "Session expired on startup, attempting refresh"
            );
            self.transition(&AuthMachineInput::SessionExpired)?;

            let refresh_token = match self.secrets.get_supabase_refresh_token()? {
                Some(t) => t,
                None => {
                    warn!("Session expired but no refresh token found, clearing session");
                    self.secrets.clear_supabase_session()?;
                    self.transition(&AuthMachineInput::RefreshFailed)?;
                    return Err(AuthError::TokenRefresh(
                        "No refresh token available".to_string(),
                    ));
                }
            };

            // Try to refresh with retry logic
            match self
                .refresh_with_backoff(&refresh_token, &meta.project_ref)
                .await
            {
                Ok((_, user_id)) => {
                    info!(user_id = %user_id, "Session refreshed successfully on startup");
                    return Ok(true);
                }
                Err(e) => {
                    warn!("Session refresh failed on startup, session cleared: {}", e);
                    return Err(e);
                }
            }
        }

        // Token is not expired locally - transition to VerifyingWithServer state
        info!(
            user_id = %meta.user_id,
            "Token not expired, verifying session with server"
        );
        self.transition(&AuthMachineInput::TokenNotExpired)?;

        // Now in VerifyingWithServer state - must call server
        match self.verify_session_with_server(&access_token).await {
            Ok(user_id) => {
                info!(
                    user_id = %user_id,
                    "Session validated on startup (verified with server)"
                );
                self.transition(&AuthMachineInput::ServerVerified)?;
                Ok(true)
            }
            Err(e) => {
                warn!(
                    user_id = %meta.user_id,
                    error = %e,
                    "Session verification failed, clearing session"
                );
                self.secrets.clear_supabase_session()?;
                self.transition(&AuthMachineInput::ServerRejected)?;
                Err(e)
            }
        }
    }

    /// Verify the session is valid by calling the Supabase /auth/v1/user endpoint.
    ///
    /// This ensures the session hasn't been revoked server-side.
    /// Returns the user ID if the session is valid.
    async fn verify_session_with_server(&self, access_token: &str) -> AuthResult<String> {
        let user_url = format!("{}/auth/v1/user", self.supabase_url);

        debug!(url = %user_url, "Verifying session with Supabase");

        let response = self
            .http_client
            .get(&user_url)
            .header("apikey", &self.supabase_publishable_key)
            .header("Authorization", format!("Bearer {}", access_token))
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            warn!(status = %status, body = %body, "Session verification failed");

            return Err(AuthError::SessionInvalid(format!(
                "Server rejected session: HTTP {}: {}",
                status, body
            )));
        }

        let user: UserResponse = response.json().await?;
        debug!(user_id = %user.id, "Session verified with server");

        Ok(user.id)
    }

    /// Get current authentication status (backward-compatible API).
    pub fn get_status(&self) -> AuthResult<AuthStatus> {
        if !self.secrets.has_supabase_session()? {
            return Ok(AuthStatus::NotLoggedIn);
        }

        let meta = self.secrets.get_supabase_session_meta()?;
        match meta {
            Some(meta) => {
                if self.secrets.is_supabase_session_expired()? {
                    Ok(AuthStatus::Expired)
                } else {
                    Ok(AuthStatus::LoggedIn {
                        user_id: meta.user_id,
                        expires_at: meta.expires_at,
                    })
                }
            }
            None => Ok(AuthStatus::NotLoggedIn),
        }
    }

    /// Check if user is logged in (with valid, non-expired session).
    pub fn is_logged_in(&self) -> AuthResult<bool> {
        if !self.secrets.has_supabase_session()? {
            return Ok(false);
        }

        // Check if expired
        if self.secrets.is_supabase_session_expired()? {
            return Ok(false);
        }

        Ok(true)
    }

    /// Get a valid access token, refreshing if necessary.
    ///
    /// Uses the FSM to track the refresh operation if needed.
    /// Returns the access token and user ID if successful.
    pub async fn get_valid_token(&self) -> AuthResult<(String, String)> {
        // Check if logged in
        if !self.secrets.has_supabase_session()? {
            return Err(AuthError::NotLoggedIn);
        }

        // Get current session data
        let access_token = self
            .secrets
            .get_supabase_access_token()?
            .ok_or(AuthError::NotLoggedIn)?;
        let refresh_token = self
            .secrets
            .get_supabase_refresh_token()?
            .ok_or(AuthError::NotLoggedIn)?;
        let meta = self
            .secrets
            .get_supabase_session_meta()?
            .ok_or(AuthError::NotLoggedIn)?;

        // Check if token is still valid
        if !self.secrets.is_supabase_session_expired()? {
            debug!("Token still valid");
            return Ok((access_token, meta.user_id));
        }

        // Token expired - transition FSM and try to refresh
        info!("Token expired, attempting refresh");
        self.transition(&AuthMachineInput::TokenExpired)?;

        self.refresh_with_backoff(&refresh_token, &meta.project_ref)
            .await
    }

    /// Refresh the session with exponential backoff retry.
    async fn refresh_with_backoff(
        &self,
        refresh_token: &str,
        project_ref: &str,
    ) -> AuthResult<(String, String)> {
        let mut last_error = None;

        for attempt in 0..self.refresh_config.max_retries {
            match self.try_refresh(refresh_token, project_ref).await {
                Ok(result) => {
                    self.transition(&AuthMachineInput::RefreshSuccess)?;
                    return Ok(result);
                }
                Err(e) if e.is_transient() => {
                    last_error = Some(e);

                    if attempt + 1 < self.refresh_config.max_retries {
                        // Signal retry (stays in Refreshing state)
                        let _ = self.transition(&AuthMachineInput::RefreshRetry);

                        let delay = self.refresh_config.delay_for_attempt(attempt);
                        debug!(
                            attempt = attempt + 1,
                            max_retries = self.refresh_config.max_retries,
                            delay_ms = delay.as_millis(),
                            "Refresh failed with transient error, retrying"
                        );
                        tokio::time::sleep(delay).await;
                    }
                }
                Err(e) => {
                    // Non-transient error, fail immediately
                    warn!("Refresh failed with non-transient error: {}", e);
                    self.secrets.clear_supabase_session()?;
                    self.transition(&AuthMachineInput::RefreshFailed)?;
                    return Err(e);
                }
            }
        }

        // Exhausted retries
        warn!(
            "Refresh failed after {} attempts",
            self.refresh_config.max_retries
        );
        self.secrets.clear_supabase_session()?;
        self.transition(&AuthMachineInput::RefreshFailed)?;

        Err(last_error.unwrap_or(AuthError::RefreshExhausted(self.refresh_config.max_retries)))
    }

    /// Single attempt to refresh the session.
    async fn try_refresh(
        &self,
        refresh_token: &str,
        project_ref: &str,
    ) -> AuthResult<(String, String)> {
        // Build refresh URL
        let refresh_url = format!(
            "{}/auth/v1/token?grant_type=refresh_token",
            self.supabase_url
        );

        debug!(url = %refresh_url, "Refreshing token");

        // Make refresh request
        let response = self
            .http_client
            .post(&refresh_url)
            .header("apikey", &self.supabase_publishable_key)
            .header("Content-Type", "application/json")
            .json(&RefreshRequest {
                refresh_token: refresh_token.to_string(),
            })
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            warn!(status = %status, body = %body, "Token refresh failed");

            // Don't clear session here - let the caller handle it based on retry logic
            return Err(AuthError::TokenRefresh(format!(
                "HTTP {}: {}",
                status, body
            )));
        }

        let data: RefreshResponse = response.json().await?;

        // Calculate new expiration time
        let expires_at = Utc::now() + Duration::seconds(data.expires_in);

        // Store new tokens
        self.secrets.set_supabase_access_token(&data.access_token)?;
        self.secrets
            .set_supabase_refresh_token(&data.refresh_token)?;
        self.secrets
            .set_supabase_session_meta(&SupabaseSessionMeta {
                user_id: data.user.id.clone(),
                email: data.user.email.clone(),
                expires_at: expires_at.to_rfc3339(),
                project_ref: project_ref.to_string(),
            })?;

        info!(user_id = %data.user.id, "Token refreshed successfully");

        Ok((data.access_token, data.user.id))
    }

    /// Login with email and password.
    ///
    /// Uses the FSM to track the login operation:
    /// - NotLoggedIn -> LoggingIn -> (LoggedIn | NotLoggedIn)
    ///
    /// Calls Supabase Auth API directly to authenticate the user.
    pub async fn login_with_password(&self, email: &str, password: &str) -> AuthResult<()> {
        // Transition to logging in state
        self.transition(&AuthMachineInput::LoginAttempt)?;

        let login_url = format!("{}/auth/v1/token?grant_type=password", self.supabase_url);

        debug!(url = %login_url, email = %email, "Attempting email/password login");

        let response = self
            .http_client
            .post(&login_url)
            .header("apikey", &self.supabase_publishable_key)
            .header("Content-Type", "application/json")
            .json(&serde_json::json!({
                "email": email,
                "password": password,
            }))
            .send()
            .await;

        let response = match response {
            Ok(r) => r,
            Err(e) => {
                self.transition(&AuthMachineInput::LoginFailed)?;
                return Err(AuthError::Http(e));
            }
        };

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            warn!(status = %status, body = %body, "Login failed");
            self.transition(&AuthMachineInput::LoginFailed)?;
            return Err(AuthError::InvalidCredentials(format!(
                "HTTP {}: {}",
                status, body
            )));
        }

        let data: RefreshResponse = match response.json().await {
            Ok(d) => d,
            Err(e) => {
                self.transition(&AuthMachineInput::LoginFailed)?;
                return Err(AuthError::Http(e));
            }
        };

        // Calculate expiration time
        let expires_at = Utc::now() + Duration::seconds(data.expires_in);

        // Extract project ref from Supabase URL (e.g., "abc123" from "https://abc123.supabase.co")
        let project_ref = self
            .supabase_url
            .replace("https://", "")
            .split('.')
            .next()
            .unwrap_or("unknown")
            .to_string();

        // Store tokens
        self.secrets.set_supabase_access_token(&data.access_token)?;
        self.secrets
            .set_supabase_refresh_token(&data.refresh_token)?;
        self.secrets
            .set_supabase_session_meta(&SupabaseSessionMeta {
                user_id: data.user.id.clone(),
                email: data.user.email.clone(),
                expires_at: expires_at.to_rfc3339(),
                project_ref,
            })?;

        // Transition to logged in
        self.transition(&AuthMachineInput::LoginSuccess)?;

        info!(user_id = %data.user.id, "Login successful");

        Ok(())
    }

    /// Logout by clearing all session data.
    ///
    /// Uses the FSM to track the logout operation:
    /// - LoggedIn -> LoggingOut -> NotLoggedIn
    pub fn logout(&self) -> AuthResult<()> {
        // Try to transition - if we're not in LoggedIn state, just clear storage anyway
        let _ = self.transition(&AuthMachineInput::LogoutRequested);

        self.secrets.clear_supabase_session()?;

        let _ = self.transition(&AuthMachineInput::LogoutComplete);

        info!("Logged out");
        Ok(())
    }

    /// Get the current user ID if logged in.
    pub fn get_user_id(&self) -> AuthResult<Option<String>> {
        match self.secrets.get_supabase_session_meta()? {
            Some(meta) => Ok(Some(meta.user_id)),
            None => Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use daemon_storage::SecureStorage;
    use std::collections::HashMap;

    /// In-memory storage for testing.
    struct MemoryStorage {
        data: Mutex<HashMap<String, String>>,
    }

    impl MemoryStorage {
        fn new() -> Self {
            Self {
                data: Mutex::new(HashMap::new()),
            }
        }
    }

    impl SecureStorage for MemoryStorage {
        fn set(&self, key: &str, value: &str) -> daemon_storage::StorageResult<()> {
            self.data
                .lock()
                .unwrap()
                .insert(key.to_string(), value.to_string());
            Ok(())
        }

        fn get(&self, key: &str) -> daemon_storage::StorageResult<Option<String>> {
            Ok(self.data.lock().unwrap().get(key).cloned())
        }

        fn delete(&self, key: &str) -> daemon_storage::StorageResult<bool> {
            Ok(self.data.lock().unwrap().remove(key).is_some())
        }
    }

    fn create_test_manager() -> SessionManager {
        let storage = Box::new(MemoryStorage::new());
        let secrets = SecretsManager::new(storage);
        SessionManager::new(secrets, "https://test.supabase.co", "test-publishable-key")
    }

    #[test]
    fn test_initial_fsm_state() {
        let manager = create_test_manager();
        assert_eq!(manager.fsm_state(), AuthState::NotLoggedIn);
    }

    #[test]
    fn test_not_logged_in() {
        let manager = create_test_manager();
        assert!(!manager.is_logged_in().unwrap());

        match manager.get_status().unwrap() {
            AuthStatus::NotLoggedIn => {}
            _ => panic!("Expected NotLoggedIn status"),
        }
    }

    #[test]
    fn test_logout() {
        let manager = create_test_manager();

        // Simulate a login by directly storing session data
        let expires_at = (Utc::now() + Duration::hours(1)).to_rfc3339();
        manager
            .secrets
            .set_supabase_session(
                "test-access-token",
                "test-refresh-token",
                "user-123",
                Some("test@example.com"),
                &expires_at,
            )
            .unwrap();

        assert!(manager.is_logged_in().unwrap());

        // Logout
        manager.logout().unwrap();
        assert!(!manager.is_logged_in().unwrap());
    }

    #[test]
    fn test_session_manager_status_logged_in() {
        let manager = create_test_manager();

        // Simulate a login
        let expires_at = (Utc::now() + Duration::hours(1)).to_rfc3339();
        manager
            .secrets
            .set_supabase_session(
                "test-access-token",
                "test-refresh-token",
                "user-456",
                Some("test@example.com"),
                &expires_at,
            )
            .unwrap();

        match manager.get_status().unwrap() {
            AuthStatus::LoggedIn { user_id, .. } => {
                assert_eq!(user_id, "user-456");
            }
            _ => panic!("Expected LoggedIn status"),
        }
    }

    #[test]
    fn test_session_manager_get_user_id_not_logged_in() {
        let manager = create_test_manager();
        assert!(manager.get_user_id().unwrap().is_none());
    }

    #[test]
    fn test_session_manager_get_user_id_logged_in() {
        let manager = create_test_manager();

        // Simulate a login
        let expires_at = (Utc::now() + Duration::hours(1)).to_rfc3339();
        manager
            .secrets
            .set_supabase_session(
                "test-access-token",
                "test-refresh-token",
                "user-789",
                Some("test@example.com"),
                &expires_at,
            )
            .unwrap();

        assert_eq!(manager.get_user_id().unwrap(), Some("user-789".to_string()));
    }

    #[test]
    fn test_fsm_tracks_login_attempt() {
        let manager = create_test_manager();

        // Start in NotLoggedIn
        assert_eq!(manager.fsm_state(), AuthState::NotLoggedIn);

        // Transition to LoggingIn
        manager.transition(&AuthMachineInput::LoginAttempt).unwrap();
        assert_eq!(manager.fsm_state(), AuthState::LoggingIn);

        // Simulate login failure
        manager.transition(&AuthMachineInput::LoginFailed).unwrap();
        assert_eq!(manager.fsm_state(), AuthState::NotLoggedIn);
    }

    #[test]
    fn test_fsm_tracks_validation() {
        let manager = create_test_manager();

        // Start validation
        manager
            .transition(&AuthMachineInput::ValidateSession)
            .unwrap();
        assert_eq!(manager.fsm_state(), AuthState::Validating);

        // No session found
        manager.transition(&AuthMachineInput::NoSession).unwrap();
        assert_eq!(manager.fsm_state(), AuthState::NotLoggedIn);
    }

    #[test]
    fn test_state_callback_invoked_on_transition() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        let manager = create_test_manager();
        let callback_count = Arc::new(AtomicUsize::new(0));
        let callback_count_clone = callback_count.clone();

        manager.set_state_callback(Box::new(move |_payload| {
            callback_count_clone.fetch_add(1, Ordering::SeqCst);
        }));

        // Make some transitions
        manager.transition(&AuthMachineInput::LoginAttempt).unwrap();
        manager.transition(&AuthMachineInput::LoginFailed).unwrap();

        // Callback should have been called twice (once per state change)
        assert_eq!(callback_count.load(Ordering::SeqCst), 2);
    }

    use std::sync::Arc;
}
