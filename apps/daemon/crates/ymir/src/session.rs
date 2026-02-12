//! Session management with automatic token refresh using FSM-based state management.
//!
//! This module provides a `SessionManager` that uses an internal finite state machine
//! to track authentication state explicitly, rather than deriving it from storage.
//! This provides better reliability, testability, and observability.

use crate::auth_fsm::{
    AuthMachine, AuthMachineInput, AuthState, AuthStateChangedPayload, RefreshConfig,
};
use crate::{AuthError, AuthResult};
use chrono::{Duration as ChronoDuration, Utc};
use daemon_storage::{SecretsManager, SupabaseSessionMeta};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::Notify;
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

/// Canonical auth snapshot used by daemon IPC and app startup gating.
#[derive(Debug, Clone)]
pub struct AuthSnapshot {
    pub state: AuthState,
    pub has_stored_session: bool,
    pub session_valid: bool,
    /// Backward-compatible alias for `session_valid`.
    pub authenticated: bool,
    pub user_id: Option<String>,
    pub email: Option<String>,
    pub expires_at: Option<String>,
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
    /// Starts at most one background worker for clock-driven reconciliation.
    clock_worker_started: AtomicBool,
    /// Wakes the background worker when session credentials change.
    clock_reconcile_notify: Notify,
}

impl SessionManager {
    /// Create a new session manager.
    pub fn new(
        secrets: SecretsManager,
        supabase_url: &str,
        supabase_publishable_key: &str,
    ) -> Self {
        let manager = Self {
            secrets,
            supabase_url: supabase_url.to_string(),
            supabase_publishable_key: supabase_publishable_key.to_string(),
            http_client: Client::new(),
            fsm: Mutex::new(AuthMachine::new()),
            refresh_config: RefreshConfig::default(),
            state_callback: Mutex::new(None),
            clock_worker_started: AtomicBool::new(false),
            clock_reconcile_notify: Notify::new(),
        };
        let _ = manager.bootstrap_pending_validation_state();
        manager
    }

    /// Create a new session manager with custom refresh configuration.
    pub fn with_refresh_config(
        secrets: SecretsManager,
        supabase_url: &str,
        supabase_publishable_key: &str,
        refresh_config: RefreshConfig,
    ) -> Self {
        let manager = Self {
            secrets,
            supabase_url: supabase_url.to_string(),
            supabase_publishable_key: supabase_publishable_key.to_string(),
            http_client: Client::new(),
            fsm: Mutex::new(AuthMachine::new()),
            refresh_config,
            state_callback: Mutex::new(None),
            clock_worker_started: AtomicBool::new(false),
            clock_reconcile_notify: Notify::new(),
        };
        let _ = manager.bootstrap_pending_validation_state();
        manager
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

    /// Start background clock reconciliation once.
    ///
    /// This implements the "proactive" part of the hybrid model.
    pub fn start_hybrid_clock_reconciliation(self: &Arc<Self>) {
        if self.clock_worker_started.swap(true, Ordering::SeqCst) {
            return;
        }

        if tokio::runtime::Handle::try_current().is_err() {
            // Unit tests without a runtime still use lazy reconciliation.
            self.clock_worker_started.store(false, Ordering::SeqCst);
            warn!("No Tokio runtime; skipping background auth clock reconciliation worker");
            return;
        }

        let weak_self = Arc::downgrade(self);
        tokio::spawn(async move {
            loop {
                let Some(manager) = weak_self.upgrade() else {
                    break;
                };

                let sleep_for = manager.next_clock_check_interval();

                tokio::select! {
                    _ = tokio::time::sleep(sleep_for) => {
                        if let Err(error) = manager.reconcile_clock_expiry_if_needed().await {
                            warn!(error = %error, "Background auth clock reconciliation failed");
                        }
                    }
                    _ = manager.clock_reconcile_notify.notified() => {
                        continue;
                    }
                }
            }
        });

        self.notify_clock_reconcile();
    }

    /// Return canonical auth snapshot, reconciling clock/state lazily on read.
    pub async fn status_snapshot(&self) -> AuthResult<AuthSnapshot> {
        self.bootstrap_pending_validation_state()?;

        self.reconcile_clock_expiry_if_needed().await?;

        let state = self.fsm_state();
        let has_stored_session = self.secrets.has_supabase_session()?;
        let meta = self.secrets.get_supabase_session_meta()?;
        let expired = if has_stored_session {
            self.secrets.is_supabase_session_expired().unwrap_or(true)
        } else {
            true
        };

        let session_valid = has_stored_session && !expired && state == AuthState::LoggedIn;

        Ok(AuthSnapshot {
            state,
            has_stored_session,
            session_valid,
            authenticated: session_valid,
            user_id: meta.as_ref().map(|m| m.user_id.clone()),
            email: meta.as_ref().and_then(|m| m.email.clone()),
            expires_at: meta.as_ref().map(|m| m.expires_at.clone()),
        })
    }

    fn bootstrap_pending_validation_state(&self) -> AuthResult<()> {
        let has_stored_session = self.secrets.has_supabase_session()?;
        let state = self.fsm_state();

        if has_stored_session && state == AuthState::NotLoggedIn {
            self.transition(&AuthMachineInput::SessionDetected)?;
        } else if !has_stored_session && state == AuthState::PendingValidation {
            let _ = self.transition(&AuthMachineInput::NoSession);
        }

        Ok(())
    }

    fn notify_clock_reconcile(&self) {
        self.clock_reconcile_notify.notify_one();
    }

    fn next_clock_check_interval(&self) -> Duration {
        let Ok(true) = self.secrets.has_supabase_session() else {
            return Duration::from_secs(300);
        };

        let Ok(Some(meta)) = self.secrets.get_supabase_session_meta() else {
            return Duration::from_secs(60);
        };

        let Ok(expires_at) = chrono::DateTime::parse_from_rfc3339(&meta.expires_at) else {
            // Parse failure will be handled by lazy reconciliation soon.
            return Duration::from_secs(1);
        };

        let trigger_at = expires_at.with_timezone(&Utc) - ChronoDuration::seconds(60);
        let now = Utc::now();
        let seconds_until_trigger = trigger_at.signed_duration_since(now).num_seconds();

        if seconds_until_trigger <= 0 {
            Duration::from_secs(1)
        } else {
            Duration::from_secs(seconds_until_trigger as u64)
        }
    }

    async fn reconcile_clock_expiry_if_needed(&self) -> AuthResult<()> {
        if !self.secrets.has_supabase_session()? {
            return Ok(());
        }

        if !self.secrets.is_supabase_session_expired()? {
            return Ok(());
        }

        match self.fsm_state() {
            AuthState::LoggedIn | AuthState::Refreshing => {
                let _ = self.get_valid_token().await;
            }
            AuthState::PendingValidation
            | AuthState::Validating
            | AuthState::VerifyingWithServer => {
                let _ = self.validate_session_on_startup().await;
            }
            AuthState::NotLoggedIn | AuthState::LoggingIn | AuthState::LoggingOut => {}
        }

        Ok(())
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
        self.bootstrap_pending_validation_state()?;

        // Transition to validating state when pending validation is required.
        match self.fsm_state() {
            AuthState::PendingValidation | AuthState::NotLoggedIn => {
                self.transition(&AuthMachineInput::ValidateSession)?;
            }
            AuthState::Validating | AuthState::VerifyingWithServer | AuthState::Refreshing => {}
            AuthState::LoggedIn => {
                if self.secrets.has_supabase_session()?
                    && !self.secrets.is_supabase_session_expired().unwrap_or(true)
                {
                    return Ok(true);
                }
            }
            AuthState::LoggingIn | AuthState::LoggingOut => {}
        }

        // Check if we have a session at all
        if !self.secrets.has_supabase_session()? {
            info!("No existing session found on startup");
            self.transition(&AuthMachineInput::NoSession)?;
            self.notify_clock_reconcile();
            return Ok(false);
        }

        // Get session metadata
        let meta = match self.secrets.get_supabase_session_meta()? {
            Some(m) => m,
            None => {
                info!("Session tokens exist but metadata is missing, clearing session");
                self.secrets.clear_supabase_session()?;
                self.transition(&AuthMachineInput::NoSession)?;
                self.notify_clock_reconcile();
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
                self.notify_clock_reconcile();
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
            if self.fsm_state() == AuthState::LoggedIn {
                self.transition(&AuthMachineInput::TokenExpired)?;
            } else {
                self.transition(&AuthMachineInput::SessionExpired)?;
            }

            let refresh_token = match self.secrets.get_supabase_refresh_token()? {
                Some(t) => t,
                None => {
                    warn!("Session expired but no refresh token found, clearing session");
                    self.secrets.clear_supabase_session()?;
                    self.transition(&AuthMachineInput::RefreshFailed)?;
                    self.notify_clock_reconcile();
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
                    self.notify_clock_reconcile();
                    return Ok(true);
                }
                Err(e) => {
                    warn!("Session refresh failed on startup, session cleared: {}", e);
                    self.notify_clock_reconcile();
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
                self.notify_clock_reconcile();
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
                self.notify_clock_reconcile();
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
        self.bootstrap_pending_validation_state()?;

        if !self.secrets.has_supabase_session()? {
            return Err(AuthError::NotLoggedIn);
        }

        // Force a startup-style validation when we're still in pre-validated states.
        if matches!(
            self.fsm_state(),
            AuthState::PendingValidation | AuthState::Validating | AuthState::VerifyingWithServer
        ) {
            if !self.validate_session_on_startup().await? {
                return Err(AuthError::NotLoggedIn);
            }
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

        // Token still valid and the FSM already confirmed this session.
        if !self.secrets.is_supabase_session_expired()? && self.fsm_state() == AuthState::LoggedIn {
            debug!("Token still valid");
            return Ok((access_token, meta.user_id));
        }

        // If we are not in LoggedIn, try to reconcile once via startup validation path.
        if self.fsm_state() != AuthState::LoggedIn {
            let validated = self.validate_session_on_startup().await?;
            if !validated {
                return Err(AuthError::NotLoggedIn);
            }

            let reconciled_token = self
                .secrets
                .get_supabase_access_token()?
                .ok_or(AuthError::NotLoggedIn)?;
            let reconciled_meta = self
                .secrets
                .get_supabase_session_meta()?
                .ok_or(AuthError::NotLoggedIn)?;

            if !self.secrets.is_supabase_session_expired()? {
                return Ok((reconciled_token, reconciled_meta.user_id));
            }
        }

        // Token expired while we are in LoggedIn -> transition to Refreshing and refresh.
        info!("Token expired, attempting refresh");
        self.transition(&AuthMachineInput::TokenExpired)?;

        let result = self
            .refresh_with_backoff(&refresh_token, &meta.project_ref)
            .await;
        self.notify_clock_reconcile();
        result
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
                    self.notify_clock_reconcile();
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
                    self.notify_clock_reconcile();
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
        self.notify_clock_reconcile();

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
        let expires_at = Utc::now() + ChronoDuration::seconds(data.expires_in);

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
        // If already logged in, logout first to allow re-login
        if self.fsm_state() == AuthState::LoggedIn {
            info!("Already logged in, logging out before re-login");
            self.logout()?;
        }

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
        let expires_at = Utc::now() + ChronoDuration::seconds(data.expires_in);

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
        self.notify_clock_reconcile();

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
        self.notify_clock_reconcile();

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

    fn create_test_manager_with_refresh_config(refresh_config: RefreshConfig) -> SessionManager {
        let storage = Box::new(MemoryStorage::new());
        let secrets = SecretsManager::new(storage);
        SessionManager::with_refresh_config(
            secrets,
            "not-a-url",
            "test-publishable-key",
            refresh_config,
        )
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
        let expires_at = (Utc::now() + ChronoDuration::hours(1)).to_rfc3339();
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
        let expires_at = (Utc::now() + ChronoDuration::hours(1)).to_rfc3339();
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
        let expires_at = (Utc::now() + ChronoDuration::hours(1)).to_rfc3339();
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

    #[tokio::test]
    async fn test_status_snapshot_reports_pending_validation_for_stored_session() {
        let manager = create_test_manager();
        let expires_at = (Utc::now() + ChronoDuration::hours(1)).to_rfc3339();

        manager
            .secrets
            .set_supabase_session(
                "test-access-token",
                "test-refresh-token",
                "user-pending",
                Some("pending@example.com"),
                &expires_at,
            )
            .unwrap();

        let snapshot = manager.status_snapshot().await.unwrap();
        assert_eq!(snapshot.state, AuthState::PendingValidation);
        assert!(snapshot.has_stored_session);
        assert!(!snapshot.session_valid);
        assert!(!snapshot.authenticated);
    }

    #[tokio::test]
    async fn test_status_snapshot_reports_valid_session_for_logged_in_state() {
        let manager = create_test_manager();
        let expires_at = (Utc::now() + ChronoDuration::hours(1)).to_rfc3339();

        manager
            .secrets
            .set_supabase_session(
                "test-access-token",
                "test-refresh-token",
                "user-valid",
                Some("valid@example.com"),
                &expires_at,
            )
            .unwrap();

        manager.transition(&AuthMachineInput::LoginAttempt).unwrap();
        manager.transition(&AuthMachineInput::LoginSuccess).unwrap();

        let snapshot = manager.status_snapshot().await.unwrap();
        assert_eq!(snapshot.state, AuthState::LoggedIn);
        assert!(snapshot.has_stored_session);
        assert!(snapshot.session_valid);
        assert!(snapshot.authenticated);
    }

    #[tokio::test]
    async fn test_status_snapshot_reconciles_expired_session_and_clears_invalid_credentials() {
        let manager = create_test_manager_with_refresh_config(RefreshConfig {
            max_retries: 0,
            initial_delay_ms: 0,
            max_delay_ms: 0,
        });
        let expires_at = (Utc::now() - ChronoDuration::hours(1)).to_rfc3339();

        manager
            .secrets
            .set_supabase_session(
                "test-access-token",
                "test-refresh-token",
                "user-expired",
                Some("expired@example.com"),
                &expires_at,
            )
            .unwrap();
        manager.transition(&AuthMachineInput::LoginAttempt).unwrap();
        manager.transition(&AuthMachineInput::LoginSuccess).unwrap();
        assert_eq!(manager.fsm_state(), AuthState::LoggedIn);

        let snapshot = manager.status_snapshot().await.unwrap();
        assert_eq!(snapshot.state, AuthState::NotLoggedIn);
        assert!(!snapshot.has_stored_session);
        assert!(!snapshot.session_valid);
        assert!(!snapshot.authenticated);
        assert!(manager
            .secrets
            .get_supabase_access_token()
            .unwrap()
            .is_none());
        assert!(manager
            .secrets
            .get_supabase_session_meta()
            .unwrap()
            .is_none());
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
