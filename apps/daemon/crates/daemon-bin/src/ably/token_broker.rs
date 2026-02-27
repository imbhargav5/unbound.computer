//! Local Ably token broker for sidecars.

use chrono::Utc;
use daemon_config_and_utils::compile_time_web_app_url;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{oneshot, RwLock};
use tokio::task::JoinHandle;
use tracing::{debug, info, warn};
use uuid::Uuid;
use auth_engine::DaemonAuthRuntime;

const CACHE_REFRESH_MARGIN_MS: i64 = 120_000;
const MAX_REQUEST_BYTES: usize = 16 * 1024;
const IO_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, Copy, Deserialize, Eq, PartialEq, Hash)]
#[serde(rename_all = "snake_case")]
enum BrokerAudience {
    DaemonFalco,
    DaemonNagato,
}

impl BrokerAudience {
    fn as_str(self) -> &'static str {
        match self {
            Self::DaemonFalco => "daemon_falco",
            Self::DaemonNagato => "daemon_nagato",
        }
    }
}

#[derive(Debug, Deserialize)]
struct BrokerTokenRequest {
    broker_token: String,
    audience: BrokerAudience,
    device_id: String,
}

#[derive(Debug, Serialize)]
struct BrokerTokenResponse {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    token_details: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Debug, Clone, Eq, Hash, PartialEq)]
struct CacheKey {
    audience: BrokerAudience,
    user_id: String,
    device_id: String,
}

#[derive(Debug, Clone)]
struct CachedToken {
    token_details: Value,
    expires_ms: Option<i64>,
}

/// Handle used to clear cached broker tokens without restarting the broker.
#[derive(Clone)]
pub struct AblyTokenBrokerCacheHandle {
    cache: Arc<RwLock<HashMap<CacheKey, CachedToken>>>,
}

impl AblyTokenBrokerCacheHandle {
    /// Clears all cached token details for every audience/device pair.
    pub async fn clear(&self) {
        let mut guard = self.cache.write().await;
        guard.clear();
    }
}

/// Runtime handles and credentials for the Ably token broker.
pub struct AblyTokenBrokerRuntime {
    #[allow(dead_code)]
    pub falco_token: String,
    #[allow(dead_code)]
    pub nagato_token: String,
    pub cache_handle: AblyTokenBrokerCacheHandle,
    pub shutdown_tx: oneshot::Sender<()>,
    pub task: JoinHandle<()>,
}

struct BrokerState {
    auth_runtime: Arc<DaemonAuthRuntime>,
    http_client: reqwest::Client,
    web_app_url: String,
    falco_token: String,
    nagato_token: String,
    cache: Arc<RwLock<HashMap<CacheKey, CachedToken>>>,
}

/// Start the local Ably token broker.
pub async fn start_ably_token_broker(
    socket_path: PathBuf,
    auth_runtime: Arc<DaemonAuthRuntime>,
) -> Result<AblyTokenBrokerRuntime, String> {
    if socket_path.exists() {
        std::fs::remove_file(&socket_path).map_err(|err| {
            format!(
                "failed to remove stale Ably broker socket {}: {}",
                socket_path.display(),
                err
            )
        })?;
    }

    let listener = UnixListener::bind(&socket_path).map_err(|err| {
        format!(
            "failed to bind Ably broker socket {}: {}",
            socket_path.display(),
            err
        )
    })?;

    let permissions = std::fs::Permissions::from_mode(0o600);
    if let Err(err) = std::fs::set_permissions(&socket_path, permissions) {
        warn!(
            socket = %socket_path.display(),
            error = %err,
            "Failed to tighten permissions on Ably broker socket"
        );
    }

    let falco_token = Uuid::new_v4().to_string();
    let nagato_token = Uuid::new_v4().to_string();
    let web_app_url = resolve_web_app_url();
    let cache = Arc::new(RwLock::new(HashMap::new()));

    let state = Arc::new(BrokerState {
        auth_runtime,
        http_client: reqwest::Client::new(),
        web_app_url,
        falco_token: falco_token.clone(),
        nagato_token: nagato_token.clone(),
        cache: cache.clone(),
    });

    let socket_for_task = socket_path.clone();
    let (shutdown_tx, shutdown_rx) = oneshot::channel();
    let task = tokio::spawn(async move {
        run_listener(listener, state, shutdown_rx).await;
        if let Err(err) = std::fs::remove_file(&socket_for_task) {
            if err.kind() != std::io::ErrorKind::NotFound {
                warn!(
                    socket = %socket_for_task.display(),
                    error = %err,
                    "Failed removing Ably broker socket during shutdown"
                );
            }
        }
    });

    info!(
        socket = %socket_path.display(),
        "Started local Ably token broker"
    );

    Ok(AblyTokenBrokerRuntime {
        falco_token,
        nagato_token,
        cache_handle: AblyTokenBrokerCacheHandle { cache },
        shutdown_tx,
        task,
    })
}

async fn run_listener(
    listener: UnixListener,
    state: Arc<BrokerState>,
    mut shutdown_rx: oneshot::Receiver<()>,
) {
    loop {
        tokio::select! {
            _ = &mut shutdown_rx => {
                info!("Shutting down local Ably token broker");
                break;
            }
            accepted = listener.accept() => {
                match accepted {
                    Ok((stream, _)) => {
                        let state = state.clone();
                        tokio::spawn(async move {
                            handle_connection(stream, state).await;
                        });
                    }
                    Err(err) => {
                        warn!(error = %err, "Failed accepting Ably token broker connection");
                    }
                }
            }
        }
    }
}

async fn handle_connection(mut stream: UnixStream, state: Arc<BrokerState>) {
    let request = match read_request(&mut stream).await {
        Ok(request) => request,
        Err(error) => {
            let _ = write_response(&mut stream, BrokerTokenResponse::error(error)).await;
            return;
        }
    };

    let response = match state.resolve_token(request).await {
        Ok(token_details) => BrokerTokenResponse::ok(token_details),
        Err(error) => BrokerTokenResponse::error(error),
    };

    let _ = write_response(&mut stream, response).await;
}

impl BrokerState {
    async fn resolve_token(&self, request: BrokerTokenRequest) -> Result<Value, String> {
        if !self.validate_broker_token(request.audience, &request.broker_token) {
            return Err("invalid broker token".to_string());
        }

        let normalized_device_id = normalize_device_id(&request.device_id)?;
        let sync_context = self
            .auth_runtime
            .current_sync_context()
            .map_err(|err| format!("failed reading auth sync context: {}", err))?
            .ok_or_else(|| "not authenticated".to_string())?;
        let expected_client_id = normalize_user_id(&sync_context.user_id);

        if sync_context.device_id.to_lowercase() != normalized_device_id {
            return Err("device_id does not match authenticated daemon device".to_string());
        }

        let cache_key = CacheKey {
            audience: request.audience,
            user_id: expected_client_id.clone(),
            device_id: normalized_device_id.clone(),
        };

        if let Some(cached) = self.get_cached_token(&cache_key).await {
            if token_client_id_matches(&cached, &expected_client_id) {
                return Ok(cached);
            }
            warn!(
                audience = request.audience.as_str(),
                expected_client_id = %expected_client_id,
                actual_client_id = %extract_token_client_id(&cached).unwrap_or("<missing>"),
                "Discarding cached Ably token due to clientId mismatch"
            );
            let mut guard = self.cache.write().await;
            guard.remove(&cache_key);
        }

        let fresh = self
            .request_fresh_token(request.audience, &normalized_device_id)
            .await?;
        if !token_client_id_matches(&fresh, &expected_client_id) {
            return Err(format!(
                "Ably token API returned mismatched clientId (expected {}, got {})",
                expected_client_id,
                extract_token_client_id(&fresh).unwrap_or("<missing>")
            ));
        }
        self.store_cached_token(cache_key, fresh.clone()).await;
        Ok(fresh)
    }

    fn validate_broker_token(&self, audience: BrokerAudience, broker_token: &str) -> bool {
        match audience {
            BrokerAudience::DaemonFalco => broker_token == self.falco_token,
            BrokerAudience::DaemonNagato => broker_token == self.nagato_token,
        }
    }

    async fn get_cached_token(&self, key: &CacheKey) -> Option<Value> {
        let now_ms = Utc::now().timestamp_millis();
        let cached = {
            let guard = self.cache.read().await;
            guard.get(key).cloned()
        };

        let Some(cached) = cached else {
            return None;
        };

        if is_cache_valid(cached.expires_ms, now_ms) {
            return Some(cached.token_details);
        }

        let mut guard = self.cache.write().await;
        guard.remove(key);
        None
    }

    async fn store_cached_token(&self, key: CacheKey, token_details: Value) {
        let expires_ms = token_details.get("expires").and_then(Value::as_i64);
        let mut guard = self.cache.write().await;
        guard.insert(
            key,
            CachedToken {
                token_details,
                expires_ms,
            },
        );
    }

    async fn request_fresh_token(
        &self,
        audience: BrokerAudience,
        device_id: &str,
    ) -> Result<Value, String> {
        let (access_token, _) = self
            .auth_runtime
            .session_manager()
            .get_valid_token()
            .await
            .map_err(|err| format!("failed to obtain valid access token: {}", err))?;

        let endpoint = format!("{}/api/v1/mobile/ably/token", self.web_app_url);
        let response = self
            .http_client
            .post(endpoint)
            .bearer_auth(access_token)
            .json(&json!({
                "deviceId": device_id,
                "audience": audience.as_str(),
            }))
            .send()
            .await
            .map_err(|err| format!("failed to request Ably token from web API: {}", err))?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(format!(
                "Ably token API returned HTTP {}: {}",
                status.as_u16(),
                body
            ));
        }

        let payload: Value = response
            .json()
            .await
            .map_err(|err| format!("Ably token API returned invalid JSON: {}", err))?;

        let valid_token = payload
            .get("token")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|token| !token.is_empty())
            .is_some();
        if !valid_token {
            return Err("Ably token API response missing token".to_string());
        }

        debug!(
            audience = audience.as_str(),
            "Fetched fresh Ably token details"
        );
        Ok(payload)
    }
}

async fn read_request(stream: &mut UnixStream) -> Result<BrokerTokenRequest, String> {
    let mut bytes = Vec::with_capacity(512);
    let mut chunk = [0_u8; 1024];

    loop {
        let read = tokio::time::timeout(IO_TIMEOUT, stream.read(&mut chunk))
            .await
            .map_err(|_| "timed out while reading broker request".to_string())?
            .map_err(|err| format!("failed reading broker request: {}", err))?;

        if read == 0 {
            break;
        }

        bytes.extend_from_slice(&chunk[..read]);
        if bytes.len() > MAX_REQUEST_BYTES {
            return Err("broker request body is too large".to_string());
        }
    }

    if bytes.is_empty() {
        return Err("empty broker request body".to_string());
    }

    serde_json::from_slice(&bytes).map_err(|err| format!("invalid broker request JSON: {}", err))
}

async fn write_response(
    stream: &mut UnixStream,
    response: BrokerTokenResponse,
) -> Result<(), String> {
    let payload = serde_json::to_vec(&response)
        .map_err(|err| format!("failed serializing broker response: {}", err))?;

    tokio::time::timeout(IO_TIMEOUT, stream.write_all(&payload))
        .await
        .map_err(|_| "timed out while writing broker response".to_string())?
        .map_err(|err| format!("failed writing broker response: {}", err))?;
    Ok(())
}

impl BrokerTokenResponse {
    fn ok(token_details: Value) -> Self {
        Self {
            ok: true,
            token_details: Some(token_details),
            error: None,
        }
    }

    fn error(error: String) -> Self {
        Self {
            ok: false,
            token_details: None,
            error: Some(error),
        }
    }
}

fn resolve_web_app_url() -> String {
    compile_time_web_app_url()
}

fn normalize_device_id(raw_device_id: &str) -> Result<String, String> {
    Uuid::parse_str(raw_device_id)
        .map(|parsed| parsed.to_string())
        .map_err(|_| "device_id must be a valid UUID".to_string())
}

fn normalize_user_id(raw_user_id: &str) -> String {
    raw_user_id.trim().to_ascii_lowercase()
}

fn extract_token_client_id(token_details: &Value) -> Option<&str> {
    token_details
        .get("clientId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

fn token_client_id_matches(token_details: &Value, expected_client_id: &str) -> bool {
    extract_token_client_id(token_details)
        .map(normalize_user_id)
        .is_some_and(|actual| actual == expected_client_id)
}

fn is_cache_valid(expires_ms: Option<i64>, now_ms: i64) -> bool {
    match expires_ms {
        Some(expires_ms) => now_ms + CACHE_REFRESH_MARGIN_MS < expires_ms,
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::{is_cache_valid, normalize_device_id, normalize_user_id, token_client_id_matches};
    use serde_json::json;

    #[test]
    fn normalize_device_id_lowercases_uuid() {
        let normalized =
            normalize_device_id("6F5DB7F9-C6EF-4D60-88F8-39F62F272F07").expect("must parse");
        assert_eq!(normalized, "6f5db7f9-c6ef-4d60-88f8-39f62f272f07");
    }

    #[test]
    fn normalize_device_id_rejects_invalid_uuid() {
        assert!(normalize_device_id("not-a-uuid").is_err());
    }

    #[test]
    fn cache_validity_respects_refresh_margin() {
        assert!(is_cache_valid(Some(1_000_000), 800_000));
        assert!(!is_cache_valid(Some(910_000), 800_000));
        assert!(!is_cache_valid(None, 800_000));
    }

    #[test]
    fn normalize_user_id_trims_and_lowercases() {
        assert_eq!(
            normalize_user_id(" 6F5DB7F9-C6EF-4D60-88F8-39F62F272F07 "),
            "6f5db7f9-c6ef-4d60-88f8-39f62f272f07"
        );
    }

    #[test]
    fn token_client_id_matches_checks_normalized_value() {
        let expected = "6f5db7f9-c6ef-4d60-88f8-39f62f272f07";
        let matching = json!({ "clientId": "6F5DB7F9-C6EF-4D60-88F8-39F62F272F07" });
        let mismatched = json!({ "clientId": "11111111-1111-1111-1111-111111111111" });
        let missing = json!({});

        assert!(token_client_id_matches(&matching, expected));
        assert!(!token_client_id_matches(&mismatched, expected));
        assert!(!token_client_id_matches(&missing, expected));
    }
}
