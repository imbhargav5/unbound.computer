//! Daemon-oriented authentication runtime.
//!
//! This module centralizes daemon auth behavior so IPC handlers and startup
//! flow use one shared authority for login/logout/status and social completion.

use crate::{AuthError, AuthResult, AuthState, SessionManager, SupabaseClient};
use base64::Engine;
use daemon_storage::{SecretsManager, SupabaseSessionMeta};
use serde::Deserialize;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tracing::{info, warn};
use uuid::Uuid;

const DEFAULT_WEB_APP_URL: &str = "https://unbound.computer";
const SOCIAL_LOGIN_POLL_INTERVAL_SECS: u64 = 2;

/// Snapshot of authentication state for IPC/status reporting.
#[derive(Debug, Clone)]
pub struct AuthSnapshot {
    pub authenticated: bool,
    pub user_id: Option<String>,
    pub email: Option<String>,
    pub expires_at: Option<String>,
    pub state: AuthState,
}

/// Sync context derived from a valid auth session.
#[derive(Debug, Clone)]
pub struct AuthSyncContext {
    pub access_token: String,
    pub user_id: String,
    pub device_id: String,
}

/// Result for a successful daemon login.
#[derive(Debug, Clone)]
pub struct AuthLoginResult {
    pub user_id: String,
    pub email: Option<String>,
    pub expires_at: String,
    pub device_id: String,
    pub access_token: String,
    pub device_private_key: [u8; 32],
    pub db_encryption_key: Option<[u8; 32]>,
}

/// Social login bootstrap information.
#[derive(Debug, Clone)]
pub struct SocialLoginStart {
    pub login_id: String,
    pub login_url: String,
}

#[derive(Debug, Deserialize)]
struct SocialLoginStatusResponse {
    status: String,
    #[serde(default)]
    session: Option<SocialLoginSession>,
    #[serde(default)]
    error: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SocialLoginSession {
    access_token: String,
    refresh_token: String,
    expires_at: String,
    user_id: String,
}

/// Shared daemon auth runtime.
#[derive(Clone)]
pub struct DaemonAuthRuntime {
    session_manager: Arc<SessionManager>,
    supabase_client: Arc<SupabaseClient>,
    secrets: Arc<Mutex<SecretsManager>>,
    http_client: reqwest::Client,
    web_app_url: String,
    supabase_url: String,
}

impl DaemonAuthRuntime {
    /// Create a new runtime with a shared session manager and secret store.
    pub fn new(
        session_manager: SessionManager,
        supabase_client: Arc<SupabaseClient>,
        secrets: Arc<Mutex<SecretsManager>>,
        supabase_url: impl Into<String>,
    ) -> Self {
        let web_app_url = std::env::var("UNBOUND_WEB_APP_URL")
            .ok()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_WEB_APP_URL.to_string())
            .trim_end_matches('/')
            .to_string();

        Self {
            session_manager: Arc::new(session_manager),
            supabase_client,
            secrets,
            http_client: reqwest::Client::new(),
            web_app_url,
            supabase_url: supabase_url.into(),
        }
    }

    /// Validate persisted session and refresh if needed.
    pub async fn validate_session_on_startup(&self) -> AuthResult<bool> {
        self.session_manager.validate_session_on_startup().await
    }

    /// Current auth status snapshot.
    pub fn status(&self) -> AuthResult<AuthSnapshot> {
        let state = self.session_manager.fsm_state();
        let meta = self.read_session_meta()?;
        let expired = self
            .secrets
            .lock()
            .unwrap()
            .is_supabase_session_expired()
            .unwrap_or(true);
        let authenticated = meta.is_some() && !expired;

        Ok(AuthSnapshot {
            authenticated,
            user_id: meta.as_ref().map(|m| m.user_id.clone()),
            email: meta.as_ref().and_then(|m| m.email.clone()),
            expires_at: meta.as_ref().map(|m| m.expires_at.clone()),
            state,
        })
    }

    /// Login directly with Supabase email/password.
    pub async fn login_with_password(
        &self,
        email: &str,
        password: &str,
        device_type: &str,
        device_name: &str,
    ) -> AuthResult<AuthLoginResult> {
        self.session_manager
            .login_with_password(email, password)
            .await?;

        let (access_token, user_id) = self.session_manager.get_valid_token().await?;
        let meta = self.read_session_meta()?.ok_or(AuthError::NotLoggedIn)?;

        self.complete_device_setup(
            &user_id,
            meta.email.clone(),
            meta.expires_at.clone(),
            &access_token,
            device_type,
            device_name,
        )
        .await
    }

    /// Begin social-provider auth flow.
    pub fn start_social_login(&self, provider: &str) -> AuthResult<SocialLoginStart> {
        if !matches!(provider, "github" | "google" | "gitlab") {
            return Err(AuthError::Config(format!(
                "Unsupported social provider: {}",
                provider
            )));
        }

        let login_id = Uuid::new_v4().to_string();
        let login_url = format!(
            "{}/cli-auth?login_id={}&provider={}",
            self.web_app_url, login_id, provider
        );

        Ok(SocialLoginStart {
            login_id,
            login_url,
        })
    }

    /// Complete social-provider login by polling web login status endpoint.
    pub async fn complete_social_login(
        &self,
        login_id: &str,
        timeout: Duration,
        device_type: &str,
        device_name: &str,
    ) -> AuthResult<AuthLoginResult> {
        let status_url = format!(
            "{}/api/cli-login-status?login_id={}",
            self.web_app_url, login_id
        );
        let deadline = tokio::time::Instant::now() + timeout;

        loop {
            if tokio::time::Instant::now() >= deadline {
                return Err(AuthError::Timeout);
            }

            let response = self.http_client.get(&status_url).send().await?;
            let status_code = response.status();
            let payload: SocialLoginStatusResponse = response.json().await?;

            match payload.status.as_str() {
                "pending" => {
                    tokio::time::sleep(Duration::from_secs(SOCIAL_LOGIN_POLL_INTERVAL_SECS)).await;
                }
                "success" => {
                    let session = payload.session.ok_or_else(|| {
                        AuthError::OAuth("Missing social session payload".to_string())
                    })?;

                    let project_ref = project_ref_from_supabase_url(&self.supabase_url);

                    {
                        let secrets = self.secrets.lock().unwrap();
                        secrets.set_supabase_access_token(&session.access_token)?;
                        secrets.set_supabase_refresh_token(&session.refresh_token)?;
                        secrets.set_supabase_session_meta(&SupabaseSessionMeta {
                            user_id: session.user_id.clone(),
                            email: None,
                            expires_at: session.expires_at.clone(),
                            project_ref,
                        })?;
                    }

                    // Reconcile FSM against stored session and verify with server.
                    if !self.validate_session_on_startup().await? {
                        return Err(AuthError::SessionInvalid(
                            "Social login completed but no valid session found".to_string(),
                        ));
                    }

                    let (access_token, user_id) = self.session_manager.get_valid_token().await?;
                    let meta = self.read_session_meta()?.ok_or(AuthError::NotLoggedIn)?;

                    return self
                        .complete_device_setup(
                            &user_id,
                            meta.email.clone(),
                            meta.expires_at.clone(),
                            &access_token,
                            device_type,
                            device_name,
                        )
                        .await;
                }
                "expired" => {
                    return Err(AuthError::Timeout);
                }
                other => {
                    let error = payload.error.unwrap_or_else(|| "unknown error".to_string());
                    return Err(AuthError::OAuth(format!(
                        "Social login failed ({} {}): {}",
                        status_code.as_u16(),
                        other,
                        error
                    )));
                }
            }
        }
    }

    /// Clear daemon auth session.
    pub fn logout(&self) -> AuthResult<()> {
        self.session_manager.logout()
    }

    /// Build sync context when fully authenticated and device identity is ready.
    pub fn current_sync_context(&self) -> AuthResult<Option<AuthSyncContext>> {
        let (meta, access_token, device_id) = {
            let secrets = self.secrets.lock().unwrap();

            if secrets.is_supabase_session_expired()? {
                return Ok(None);
            }

            let meta = match secrets.get_supabase_session_meta()? {
                Some(meta) => meta,
                None => return Ok(None),
            };

            let access_token = match secrets.get_supabase_access_token()? {
                Some(token) => token,
                None => return Ok(None),
            };

            let device_id = match secrets.get_device_id()? {
                Some(id) => id,
                None => return Ok(None),
            };

            (meta, access_token, device_id)
        };

        Ok(Some(AuthSyncContext {
            access_token,
            user_id: meta.user_id,
            device_id,
        }))
    }

    /// Expose the underlying session manager for advanced callers.
    pub fn session_manager(&self) -> Arc<SessionManager> {
        self.session_manager.clone()
    }

    fn read_session_meta(&self) -> AuthResult<Option<SupabaseSessionMeta>> {
        let secrets = self.secrets.lock().unwrap();
        Ok(secrets.get_supabase_session_meta()?)
    }

    async fn complete_device_setup(
        &self,
        user_id: &str,
        email: Option<String>,
        expires_at: String,
        access_token: &str,
        device_type: &str,
        device_name: &str,
    ) -> AuthResult<AuthLoginResult> {
        let (device_id, public_key_b64, private_key_arr, db_encryption_key) =
            tokio::task::spawn_blocking({
                let secrets = self.secrets.clone();
                move || -> AuthResult<(String, String, [u8; 32], Option<[u8; 32]>)> {
                    let secrets = secrets.lock().unwrap();

                    let device_id = match secrets.get_device_id()? {
                        Some(id) => id,
                        None => {
                            let id = Uuid::new_v4().to_string();
                            secrets.set_device_id(&id)?;
                            id
                        }
                    };

                    let private_key = secrets.ensure_device_private_key()?;
                    let private_key_arr: [u8; 32] =
                        private_key.clone().try_into().map_err(|_| {
                            daemon_storage::StorageError::Encoding(
                                "Invalid private key length".to_string(),
                            )
                        })?;
                    let public_key =
                        daemon_config_and_utils::hybrid_crypto::public_key_from_private(&private_key_arr);
                    let public_key_b64 =
                        base64::engine::general_purpose::STANDARD.encode(public_key);
                    let db_encryption_key = secrets.get_database_encryption_key()?;

                    Ok((
                        device_id,
                        public_key_b64,
                        private_key_arr,
                        db_encryption_key,
                    ))
                }
            })
            .await
            .map_err(|e| AuthError::Config(format!("Device setup task failed: {}", e)))??;

        if let Err(error) = self
            .supabase_client
            .upsert_device(
                &device_id,
                user_id,
                device_type,
                device_name,
                &public_key_b64,
                access_token,
            )
            .await
        {
            warn!("Device registration failed after login: {}", error);
        } else {
            info!(
                user_id = %user_id,
                device_id = %device_id,
                "Auth login complete and device registered"
            );
        }

        Ok(AuthLoginResult {
            user_id: user_id.to_string(),
            email,
            expires_at,
            device_id,
            access_token: access_token.to_string(),
            device_private_key: private_key_arr,
            db_encryption_key,
        })
    }
}

fn project_ref_from_supabase_url(supabase_url: &str) -> String {
    if let Ok(parsed) = url::Url::parse(supabase_url) {
        if let Some(host) = parsed.host_str() {
            return host.split('.').next().unwrap_or("default").to_string();
        }
    }

    supabase_url
        .replace("https://", "")
        .replace("http://", "")
        .split('.')
        .next()
        .unwrap_or("default")
        .to_string()
}
