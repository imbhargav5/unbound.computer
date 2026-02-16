use crate::app::{BillingQuotaSnapshot, DaemonState};
use crate::itachi::channels::build_session_secrets_channel;
use crate::itachi::contracts::{
    DecisionResultPayload, RemoteCommandEnvelope, RemoteCommandResponse,
    SessionSecretResponsePayload, UmSecretRequestCommand, REMOTE_COMMAND_RESPONSE_EVENT,
    SESSION_SECRET_RESPONSE_EVENT,
};
use crate::itachi::errors::ResponseErrorCode;
use crate::itachi::handler::handle_remote_command;
use crate::itachi::idempotency::BeginResult;
use crate::itachi::ports::{DecisionKind, Effect, HandlerDeps, LogLevel};
use armin::{SessionReader, SessionWriter};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use daemon_config_and_utils::{compile_time_web_app_url, encrypt_for_device};
use std::path::Path;
use std::time::Instant;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tokio::time::{interval, sleep, Duration};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

const NONCE_SIZE: usize = 12;
const MIN_CIPHERTEXT_WITH_TAG_SIZE: usize = 16;
const BILLING_USAGE_REFRESH_INTERVAL_SECS: u64 = 300;
const BILLING_USAGE_STALE_AFTER_MS: i64 = 5 * 60 * 1000;

const FALCO_TYPE_SIDE_EFFECT: u8 = 0x03;
const FALCO_TYPE_PUBLISH_ACK: u8 = 0x04;
const FALCO_STATUS_SUCCESS: u8 = 0x01;
const FALCO_STATUS_FAILED: u8 = 0x02;
const FALCO_SIDE_EFFECT_HEADER_SIZE: usize = 24;
const FALCO_PUBLISH_ACK_HEADER_SIZE: usize = 24;

const FALCO_RETRY_ATTEMPTS: usize = 3;
const FALCO_BACKOFF_BASE_MS: u64 = 200;
type RemoteCommandDispatchError = (String, String, Option<serde_json::Value>);

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct BillingUsageStatusPayload {
    plan: String,
    gateway: String,
    period_start: String,
    period_end: String,
    commands_limit: i64,
    commands_used: i64,
    commands_remaining: i64,
    enforcement_state: String,
    updated_at: String,
}

pub struct DecisionOutcome {
    pub decision: DecisionKind,
    pub result_json: Vec<u8>,
}

impl DecisionOutcome {
    fn from_payload(decision: DecisionKind, payload: &DecisionResultPayload) -> Self {
        let result_json = serde_json::to_vec(payload).unwrap_or_else(|err| {
            error!(error = %err, "Failed to serialize decision payload, using fallback");
            br#"{"schema_version":1,"status":"rejected","reason_code":"internal_error","message":"failed to serialize decision payload"}"#.to_vec()
        });
        Self {
            decision,
            result_json,
        }
    }
}

pub async fn handle_remote_command_payload(state: DaemonState, payload: &[u8]) -> DecisionOutcome {
    let deps = HandlerDeps {
        local_device_id: state.device_id.lock().unwrap().clone(),
        now_ms: chrono::Utc::now().timestamp_millis(),
    };

    let effects = handle_remote_command(payload, &deps);
    evaluate_effects(state, effects).await
}

pub fn spawn_billing_quota_refresh_loop(state: DaemonState) {
    tokio::spawn(async move {
        let mut ticker = interval(Duration::from_secs(BILLING_USAGE_REFRESH_INTERVAL_SECS));
        loop {
            ticker.tick().await;
            refresh_billing_usage_cache(&state, "periodic").await;
        }
    });
}

async fn evaluate_effects(state: DaemonState, effects: Vec<Effect>) -> DecisionOutcome {
    let mut outcome = DecisionOutcome::from_payload(
        DecisionKind::DoNotAck,
        &DecisionResultPayload::rejected(
            crate::itachi::errors::DecisionReasonCode::InternalError,
            "itachi did not produce a decision payload",
            None,
            None,
        ),
    );

    for effect in effects {
        match effect {
            Effect::ReturnDecision { decision, payload } => {
                outcome = DecisionOutcome::from_payload(decision, &payload);
            }
            Effect::ProcessUmSecretRequest { request } => {
                let state_for_task = state.clone();
                tokio::spawn(async move {
                    process_um_secret_request(state_for_task, request).await;
                });
            }
            Effect::ExecuteRemoteCommand { envelope } => {
                let state_for_task = state.clone();
                tokio::spawn(async move {
                    execute_remote_command(state_for_task, envelope).await;
                });
            }
            Effect::PublishRemoteResponse { response } => {
                let state_for_task = state.clone();
                tokio::spawn(async move {
                    if let Err(err) =
                        publish_remote_command_response(&state_for_task, &response).await
                    {
                        warn!(
                            request_id = %response.request_id,
                            error = %err,
                            "Failed to publish remote command response"
                        );
                    }
                });
            }
            Effect::RecordMetric { name } => {
                debug!(metric = name, "itachi metric");
            }
            Effect::Log { level, message } => match level {
                LogLevel::Debug => debug!("{message}"),
                LogLevel::Info => info!("{message}"),
                LogLevel::Warn => warn!("{message}"),
                LogLevel::Error => error!("{message}"),
            },
        }
    }

    outcome
}

async fn process_um_secret_request(state: DaemonState, request: UmSecretRequestCommand) {
    let key = idempotency_key(&request);
    let now = Instant::now();

    let begin_result = {
        let mut store = state.itachi_idempotency.lock().unwrap();
        store.begin(&key, now)
    };

    match begin_result {
        BeginResult::InFlight => {
            debug!(request_id = %request.request_id, "Duplicate in-flight UM secret request");
            return;
        }
        BeginResult::Completed(payload) => {
            debug!(request_id = %request.request_id, "Replaying completed UM secret response");
            if let Err(err) = publish_session_secret_response(&state, &payload).await {
                warn!(
                    request_id = %request.request_id,
                    error = %err,
                    "Failed to replay completed session secret response"
                );
            }
            return;
        }
        BeginResult::New => {}
    }

    let mut response = build_response_payload(&state, &request).await;

    if let Err(err) = publish_session_secret_response(&state, &response).await {
        warn!(
            request_id = %request.request_id,
            error = %err,
            "Publishing UM secret response failed"
        );
        response = SessionSecretResponsePayload::error(
            request.request_id.clone(),
            request.session_id.clone(),
            request.target_device_id.clone(),
            request.requester_device_id.clone(),
            ResponseErrorCode::PublishFailed,
            chrono::Utc::now().timestamp_millis(),
        );

        if let Err(fallback_err) = publish_session_secret_response(&state, &response).await {
            warn!(
                request_id = %request.request_id,
                error = %fallback_err,
                "Publishing fallback publish_failed response also failed"
            );
        }
    }

    {
        let mut store = state.itachi_idempotency.lock().unwrap();
        store.complete(&key, response, Instant::now());
    }
}

/// Execute a generic remote command and publish the response via Falco.
async fn execute_remote_command(state: DaemonState, envelope: RemoteCommandEnvelope) {
    info!(
        request_id = %envelope.request_id,
        command_type = %envelope.command_type,
        "Executing remote command"
    );

    if should_reject_for_cached_over_quota(&state) {
        info!(
            request_id = %envelope.request_id,
            command_type = %envelope.command_type,
            "Rejecting remote command due to cached over_quota status"
        );
        let response = RemoteCommandResponse::error(
            envelope.request_id.clone(),
            envelope.command_type.clone(),
            "quota_exceeded",
            "remote command quota exceeded",
        );
        if let Err(err) = publish_remote_command_response(&state, &response).await {
            warn!(
                request_id = %envelope.request_id,
                command_type = %envelope.command_type,
                error = %err,
                "Failed to publish quota-exceeded remote command response"
            );
        }
        schedule_quota_refresh(state, "post_command_over_quota");
        return;
    }

    let result = dispatch_command(&state, &envelope).await;

    let response = match result {
        Ok(value) => RemoteCommandResponse::ok(
            envelope.request_id.clone(),
            envelope.command_type.clone(),
            value,
        ),
        Err((error_code, error_message, error_data)) => RemoteCommandResponse::error_with_data(
            envelope.request_id.clone(),
            envelope.command_type.clone(),
            error_code,
            error_message,
            error_data,
        ),
    };

    if let Err(err) = publish_remote_command_response(&state, &response).await {
        warn!(
            request_id = %envelope.request_id,
            command_type = %envelope.command_type,
            error = %err,
            "Failed to publish remote command response"
        );
    }

    schedule_usage_event_and_refresh(
        state,
        envelope.request_id.clone(),
        envelope.command_type.clone(),
    );
}

fn schedule_quota_refresh(state: DaemonState, reason: &'static str) {
    tokio::spawn(async move {
        refresh_billing_usage_cache(&state, reason).await;
    });
}

fn schedule_usage_event_and_refresh(state: DaemonState, request_id: String, command_type: String) {
    tokio::spawn(async move {
        if let Err(err) = emit_usage_event(&state, &request_id).await {
            warn!(
                request_id = %request_id,
                command_type = %command_type,
                error = %err,
                "Failed to emit remote command billing usage event"
            );
        }
        refresh_billing_usage_cache(&state, "post_command").await;
    });
}

fn should_reject_for_cached_over_quota(state: &DaemonState) -> bool {
    let sync_context = match state.auth_runtime.current_sync_context() {
        Ok(Some(sync_context)) => sync_context,
        Ok(None) => return false,
        Err(err) => {
            debug!(error = %err, "Quota gate skipped: auth context unavailable");
            return false;
        }
    };

    let now_ms = chrono::Utc::now().timestamp_millis();
    let guard = state.billing_quota_cache.lock().unwrap();
    let Some(snapshot) = guard.snapshot.as_ref() else {
        return false;
    };

    if snapshot.user_id != sync_context.user_id || snapshot.device_id != sync_context.device_id {
        return false;
    }

    should_enforce_over_quota(Some(snapshot), now_ms)
}

fn should_enforce_over_quota(snapshot: Option<&BillingQuotaSnapshot>, now_ms: i64) -> bool {
    let Some(snapshot) = snapshot else {
        return false;
    };
    if snapshot.enforcement_state != "over_quota" {
        return false;
    }
    if now_ms - snapshot.fetched_at_ms > BILLING_USAGE_STALE_AFTER_MS {
        return false;
    }
    true
}

async fn refresh_billing_usage_cache(state: &DaemonState, reason: &str) {
    if !begin_cache_refresh(state) {
        return;
    }

    let result = fetch_usage_status_snapshot(state).await;
    let mut guard = state.billing_quota_cache.lock().unwrap();
    guard.refresh_in_flight = false;

    match result {
        Ok(Some(snapshot)) => {
            debug!(
                reason,
                plan = %snapshot.plan,
                gateway = %snapshot.gateway,
                enforcement_state = %snapshot.enforcement_state,
                commands_limit = snapshot.commands_limit,
                commands_used = snapshot.commands_used,
                commands_remaining = snapshot.commands_remaining,
                updated_at = %snapshot.updated_at,
                "Updated billing quota cache snapshot"
            );
            guard.snapshot = Some(snapshot);
        }
        Ok(None) => {
            guard.snapshot = None;
        }
        Err(err) => {
            warn!(reason, error = %err, "Failed to refresh billing quota cache");
        }
    }
}

fn begin_cache_refresh(state: &DaemonState) -> bool {
    let mut guard = state.billing_quota_cache.lock().unwrap();
    if guard.refresh_in_flight {
        return false;
    }
    guard.refresh_in_flight = true;
    true
}

async fn fetch_usage_status_snapshot(
    state: &DaemonState,
) -> Result<Option<BillingQuotaSnapshot>, String> {
    let sync_context = match state.auth_runtime.current_sync_context() {
        Ok(Some(sync_context)) => sync_context,
        Ok(None) => return Ok(None),
        Err(err) => return Err(format!("failed to get auth sync context: {err}")),
    };

    let (access_token, _) = state
        .auth_runtime
        .session_manager()
        .get_valid_token()
        .await
        .map_err(|err| format!("failed to obtain valid access token: {err}"))?;

    let endpoint = format!(
        "{}/api/v1/mobile/billing/usage-status?deviceId={}",
        resolve_web_app_url(),
        urlencoding::encode(&sync_context.device_id)
    );

    let response = reqwest::Client::new()
        .get(endpoint)
        .bearer_auth(access_token)
        .send()
        .await
        .map_err(|err| format!("failed to call billing usage-status endpoint: {err}"))?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!(
            "billing usage-status endpoint returned HTTP {}: {}",
            status.as_u16(),
            body
        ));
    }

    let payload: BillingUsageStatusPayload = response
        .json()
        .await
        .map_err(|err| format!("invalid billing usage-status payload: {err}"))?;

    Ok(Some(BillingQuotaSnapshot {
        user_id: sync_context.user_id,
        device_id: sync_context.device_id,
        plan: payload.plan,
        gateway: payload.gateway,
        period_start: payload.period_start,
        period_end: payload.period_end,
        enforcement_state: payload.enforcement_state,
        commands_limit: payload.commands_limit,
        commands_used: payload.commands_used,
        commands_remaining: payload.commands_remaining,
        updated_at: payload.updated_at,
        fetched_at_ms: chrono::Utc::now().timestamp_millis(),
    }))
}

async fn emit_usage_event(state: &DaemonState, request_id: &str) -> Result<(), String> {
    let sync_context = match state.auth_runtime.current_sync_context() {
        Ok(Some(sync_context)) => sync_context,
        Ok(None) => return Ok(()),
        Err(err) => return Err(format!("failed to get auth sync context: {err}")),
    };

    let (access_token, _) = state
        .auth_runtime
        .session_manager()
        .get_valid_token()
        .await
        .map_err(|err| format!("failed to obtain valid access token: {err}"))?;

    let endpoint = format!(
        "{}/api/v1/mobile/billing/usage-events",
        resolve_web_app_url()
    );
    let response = reqwest::Client::new()
        .post(endpoint)
        .bearer_auth(access_token)
        .json(&serde_json::json!({
            "deviceId": sync_context.device_id,
            "requestId": request_id,
            "usageType": "remote_commands",
            "quantity": 1,
            "occurredAt": chrono::Utc::now().to_rfc3339(),
        }))
        .send()
        .await
        .map_err(|err| format!("failed to call billing usage-events endpoint: {err}"))?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!(
            "billing usage-events endpoint returned HTTP {}: {}",
            status.as_u16(),
            body
        ));
    }

    Ok(())
}

fn resolve_web_app_url() -> String {
    compile_time_web_app_url()
}

/// Dispatch a remote command to the appropriate handler function.
/// Returns Ok(result_json) or Err((error_code, error_message, error_data)).
async fn dispatch_command(
    state: &DaemonState,
    envelope: &RemoteCommandEnvelope,
) -> Result<serde_json::Value, RemoteCommandDispatchError> {
    match classify_remote_command_type(&envelope.command_type) {
        Some(RemoteCommandType::SessionCreateV1) => {
            crate::ipc::handlers::session::create_session_core(state, &envelope.params)
                .await
                .map_err(|err| err.into_response_parts())
        }
        Some(RemoteCommandType::ClaudeSendV1) => {
            crate::ipc::handlers::claude::claude_send_core(state, &envelope.params)
                .await
                .map_err(|(code, message)| (code, message, None))
        }
        Some(RemoteCommandType::ClaudeStopV1) => {
            crate::ipc::handlers::claude::claude_stop_core(state, &envelope.params)
                .await
                .map_err(|(code, message)| (code, message, None))
        }
        Some(RemoteCommandType::GitCommitV1) => {
            crate::ipc::handlers::git::git_commit_core(state, &envelope.params)
                .await
                .map_err(|err| (err.code, err.message, None))
        }
        Some(RemoteCommandType::GitPushV1) => {
            crate::ipc::handlers::git::git_push_core(state, &envelope.params)
                .await
                .map_err(|err| (err.code, err.message, None))
        }
        Some(RemoteCommandType::GhPrCreateV1) => {
            crate::ipc::handlers::gh::gh_pr_create_core(state, &envelope.params)
                .await
                .map_err(|err| (err.code, err.message, None))
        }
        Some(RemoteCommandType::GhPrViewV1) => {
            crate::ipc::handlers::gh::gh_pr_view_core(state, &envelope.params)
                .await
                .map_err(|err| (err.code, err.message, None))
        }
        Some(RemoteCommandType::GhPrListV1) => {
            crate::ipc::handlers::gh::gh_pr_list_core(state, &envelope.params)
                .await
                .map_err(|err| (err.code, err.message, None))
        }
        Some(RemoteCommandType::GhPrChecksV1) => {
            crate::ipc::handlers::gh::gh_pr_checks_core(state, &envelope.params)
                .await
                .map_err(|err| (err.code, err.message, None))
        }
        Some(RemoteCommandType::GhPrMergeV1) => {
            crate::ipc::handlers::gh::gh_pr_merge_core(state, &envelope.params)
                .await
                .map_err(|err| (err.code, err.message, None))
        }
        None => Err((
            "unsupported_command_type".to_string(),
            format!("command type {} is not supported", envelope.command_type),
            None,
        )),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RemoteCommandType {
    SessionCreateV1,
    ClaudeSendV1,
    ClaudeStopV1,
    GitCommitV1,
    GitPushV1,
    GhPrCreateV1,
    GhPrViewV1,
    GhPrListV1,
    GhPrChecksV1,
    GhPrMergeV1,
}

fn classify_remote_command_type(command_type: &str) -> Option<RemoteCommandType> {
    match command_type {
        "session.create.v1" => Some(RemoteCommandType::SessionCreateV1),
        "claude.send.v1" => Some(RemoteCommandType::ClaudeSendV1),
        "claude.stop.v1" => Some(RemoteCommandType::ClaudeStopV1),
        "git.commit.v1" => Some(RemoteCommandType::GitCommitV1),
        "git.push.v1" => Some(RemoteCommandType::GitPushV1),
        "gh.pr.create.v1" => Some(RemoteCommandType::GhPrCreateV1),
        "gh.pr.view.v1" => Some(RemoteCommandType::GhPrViewV1),
        "gh.pr.list.v1" => Some(RemoteCommandType::GhPrListV1),
        "gh.pr.checks.v1" => Some(RemoteCommandType::GhPrChecksV1),
        "gh.pr.merge.v1" => Some(RemoteCommandType::GhPrMergeV1),
        _ => None,
    }
}

/// Publish a remote command response via Falco to the requester's channel.
async fn publish_remote_command_response(
    state: &DaemonState,
    response: &RemoteCommandResponse,
) -> Result<(), String> {
    let device_id = state
        .device_id
        .lock()
        .unwrap()
        .clone()
        .ok_or_else(|| "local device_id unavailable".to_string())?;

    let channel = format!("remote:{}:commands", device_id);
    let envelope = FalcoPublishEnvelope {
        effect_type: "remote_command_response",
        channel,
        event: REMOTE_COMMAND_RESPONSE_EVENT,
        payload: response,
    };

    let json_payload =
        serde_json::to_vec(&envelope).map_err(|err| format!("failed to encode response: {err}"))?;

    publish_via_falco_with_retry(&state.paths.falco_socket_file(), &json_payload).await
}

async fn build_response_payload(
    state: &DaemonState,
    request: &UmSecretRequestCommand,
) -> SessionSecretResponsePayload {
    let created_at_ms = chrono::Utc::now().timestamp_millis();
    let base_error = |code| {
        SessionSecretResponsePayload::error(
            request.request_id.clone(),
            request.session_id.clone(),
            request.target_device_id.clone(),
            request.requester_device_id.clone(),
            code,
            created_at_ms,
        )
    };

    let sync_context = match state.auth_runtime.current_sync_context() {
        Ok(Some(ctx)) => ctx,
        Ok(None) => return base_error(ResponseErrorCode::InternalError),
        Err(err) => {
            warn!(
                request_id = %request.request_id,
                error = %err,
                "Failed to get auth sync context"
            );
            return base_error(ResponseErrorCode::InternalError);
        }
    };

    let requester_device = match state
        .supabase_client
        .fetch_device_by_id(&request.requester_device_id, &sync_context.access_token)
        .await
    {
        Ok(Some(device)) => device,
        Ok(None) => return base_error(ResponseErrorCode::RequesterKeyNotFound),
        Err(err) => {
            warn!(
                request_id = %request.request_id,
                error = %err,
                "Failed to fetch requester device"
            );
            return base_error(ResponseErrorCode::RequesterKeyNotFound);
        }
    };

    if requester_device.user_id != sync_context.user_id {
        return base_error(ResponseErrorCode::InternalError);
    }

    let requester_public_key_b64 = match requester_device.public_key.as_deref() {
        Some(value) if !value.trim().is_empty() => value,
        _ => return base_error(ResponseErrorCode::RequesterKeyNotFound),
    };

    let requester_public_key = match decode_key_32(requester_public_key_b64) {
        Ok(key) => key,
        Err(_) => return base_error(ResponseErrorCode::RequesterKeyNotFound),
    };

    let session_secret_plaintext = match load_session_secret_plaintext(state, &request.session_id) {
        Ok(secret) => secret,
        Err(err) => {
            warn!(
                request_id = %request.request_id,
                session_id = %request.session_id,
                error = %err,
                "Failed to load session secret"
            );
            return base_error(ResponseErrorCode::SessionSecretNotFound);
        }
    };

    let (encapsulation_pubkey, encrypted) = match encrypt_for_device(
        session_secret_plaintext.as_bytes(),
        &requester_public_key,
        &request.session_id,
    ) {
        Ok(v) => v,
        Err(err) => {
            warn!(
                request_id = %request.request_id,
                error = %err,
                "Failed to encrypt session secret for requester device"
            );
            return base_error(ResponseErrorCode::EncryptionFailed);
        }
    };

    if encrypted.len() < NONCE_SIZE + MIN_CIPHERTEXT_WITH_TAG_SIZE {
        return base_error(ResponseErrorCode::EncryptionFailed);
    }

    let nonce_b64 = BASE64.encode(&encrypted[..NONCE_SIZE]);
    let ciphertext_b64 = BASE64.encode(&encrypted[NONCE_SIZE..]);
    let encapsulation_pubkey_b64 = BASE64.encode(encapsulation_pubkey);

    SessionSecretResponsePayload::ok(
        request.request_id.clone(),
        request.session_id.clone(),
        request.target_device_id.clone(),
        request.requester_device_id.clone(),
        ciphertext_b64,
        encapsulation_pubkey_b64,
        nonce_b64,
        created_at_ms,
    )
}

fn load_session_secret_plaintext(state: &DaemonState, session_id: &str) -> Result<String, String> {
    let db_key = state.db_encryption_key.lock().unwrap().to_owned();

    let armin_result = state
        .armin
        .get_session_secret(&armin::SessionId::from_string(session_id))
        .map_err(|err| format!("failed to get session secret: {err}"));

    let mut terminal_error = "session secret not found".to_string();
    let mut should_repair_armin = false;

    if let Ok(Some(session_secret)) = &armin_result {
        if let Some(db_key) = db_key {
            match daemon_database::decrypt_content(
                &db_key,
                &session_secret.nonce,
                &session_secret.encrypted_secret,
            ) {
                Ok(plaintext) => {
                    return String::from_utf8(plaintext)
                        .map_err(|err| format!("session secret is not UTF-8: {err}"));
                }
                Err(err) => {
                    terminal_error = format!("failed to decrypt session secret: {err}");
                    should_repair_armin = true;
                }
            }
        } else {
            terminal_error = "missing database encryption key".to_string();
            should_repair_armin = true;
        }
    } else if matches!(armin_result, Ok(None)) {
        should_repair_armin = true;
    } else if let Err(err) = &armin_result {
        terminal_error = err.clone();
    }

    // Fallback 1: in-memory session secret cache loaded from Supabase/keychain.
    let cached_key = {
        let cache = state.session_secret_cache.inner();
        let key = cache.lock().unwrap().get(session_id).cloned();
        key
    };
    if let Some(key) = cached_key {
        let secret = format_session_secret_from_key_bytes(&key);
        if should_repair_armin {
            match repair_armin_session_secret_from_plaintext(state, session_id, &secret, db_key) {
                Ok(()) => info!(
                    session_id = %session_id,
                    "Recovered session secret via cache and repaired Armin record"
                ),
                Err(err) => warn!(
                    session_id = %session_id,
                    error = %err,
                    "Recovered session secret via cache but failed to repair Armin record"
                ),
            }
        }
        return Ok(secret);
    }

    // Fallback 2: keychain (legacy path).
    if let Some(secret) = state
        .secrets
        .lock()
        .unwrap()
        .get_session_secret(session_id)
        .map_err(|err| format!("failed to read session secret from keychain: {err}"))?
    {
        daemon_storage::SecretsManager::parse_session_secret(&secret)
            .map_err(|err| format!("invalid keychain session secret format: {err}"))?;
        if should_repair_armin {
            match repair_armin_session_secret_from_plaintext(state, session_id, &secret, db_key) {
                Ok(()) => info!(
                    session_id = %session_id,
                    "Recovered session secret via keychain and repaired Armin record"
                ),
                Err(err) => warn!(
                    session_id = %session_id,
                    error = %err,
                    "Recovered session secret via keychain but failed to repair Armin record"
                ),
            }
        }
        return Ok(secret);
    }

    Err(terminal_error)
}

fn repair_armin_session_secret_from_plaintext(
    state: &DaemonState,
    session_id: &str,
    plaintext_secret: &str,
    db_key: Option<[u8; 32]>,
) -> Result<(), String> {
    let db_key = db_key.ok_or_else(|| "missing database encryption key".to_string())?;
    let nonce = daemon_database::generate_nonce();
    let encrypted_secret =
        daemon_database::encrypt_content(&db_key, &nonce, plaintext_secret.as_bytes())
            .map_err(|err| format!("failed to encrypt recovered session secret: {err}"))?;

    let secret = armin::NewSessionSecret {
        session_id: armin::SessionId::from_string(session_id),
        encrypted_secret,
        nonce: nonce.to_vec(),
    };

    state
        .armin
        .set_session_secret(secret)
        .map_err(|err| format!("failed to persist recovered session secret to Armin: {err}"))
}

fn format_session_secret_from_key_bytes(key: &[u8]) -> String {
    let base64url = BASE64
        .encode(key)
        .replace('+', "-")
        .replace('/', "_")
        .trim_end_matches('=')
        .to_string();
    format!("sess_{base64url}")
}

fn decode_key_32(value_b64: &str) -> Result<[u8; 32], String> {
    let bytes = BASE64
        .decode(value_b64)
        .map_err(|err| format!("base64 decode failed: {err}"))?;
    let arr: [u8; 32] = bytes
        .try_into()
        .map_err(|_| "public key must be 32 bytes".to_string())?;
    Ok(arr)
}

fn idempotency_key(request: &UmSecretRequestCommand) -> String {
    format!(
        "{}:{}:{}",
        request.request_id, request.requester_device_id, request.target_device_id
    )
}

async fn publish_session_secret_response(
    state: &DaemonState,
    payload: &SessionSecretResponsePayload,
) -> Result<(), String> {
    let envelope = FalcoPublishEnvelope {
        effect_type: "um_secret_response",
        channel: build_session_secrets_channel(
            &payload.sender_device_id,
            &payload.receiver_device_id,
        ),
        event: SESSION_SECRET_RESPONSE_EVENT,
        payload,
    };

    let json_payload =
        serde_json::to_vec(&envelope).map_err(|err| format!("failed to encode response: {err}"))?;

    publish_via_falco_with_retry(&state.paths.falco_socket_file(), &json_payload).await
}

async fn publish_via_falco_with_retry(socket_path: &Path, payload: &[u8]) -> Result<(), String> {
    let mut last_err = String::new();
    for attempt in 1..=FALCO_RETRY_ATTEMPTS {
        match publish_via_falco_once(socket_path, payload).await {
            Ok(()) => return Ok(()),
            Err(err) => {
                last_err = err;
                if attempt < FALCO_RETRY_ATTEMPTS {
                    let delay = FALCO_BACKOFF_BASE_MS * (1_u64 << (attempt - 1));
                    sleep(Duration::from_millis(delay)).await;
                }
            }
        }
    }
    Err(format!(
        "falco publish failed after {FALCO_RETRY_ATTEMPTS} attempts: {last_err}"
    ))
}

async fn publish_via_falco_once(socket_path: &Path, payload: &[u8]) -> Result<(), String> {
    let effect_id = Uuid::new_v4();
    let frame = encode_side_effect_frame(effect_id, payload);
    let mut stream = UnixStream::connect(socket_path)
        .await
        .map_err(|err| format!("failed to connect to falco socket: {err}"))?;

    stream
        .write_all(&frame)
        .await
        .map_err(|err| format!("falco write failed: {err}"))?;

    let ack = read_publish_ack(&mut stream).await?;
    if ack.effect_id != effect_id {
        return Err(format!(
            "falco ack mismatch: expected {}, got {}",
            effect_id, ack.effect_id
        ));
    }

    match ack.status {
        FALCO_STATUS_SUCCESS => Ok(()),
        FALCO_STATUS_FAILED => {
            if ack.error_message.is_empty() {
                Err("falco publish failed".to_string())
            } else {
                Err(format!("falco publish failed: {}", ack.error_message))
            }
        }
        other => Err(format!("falco returned unknown status: 0x{other:02x}")),
    }
}

#[derive(Debug, serde::Serialize)]
struct FalcoPublishEnvelope<'a, T> {
    #[serde(rename = "type")]
    effect_type: &'a str,
    channel: String,
    event: &'a str,
    payload: T,
}

#[derive(Debug)]
struct PublishAckFrame {
    effect_id: Uuid,
    status: u8,
    error_message: String,
}

fn encode_side_effect_frame(effect_id: Uuid, payload: &[u8]) -> Vec<u8> {
    let payload_len = payload.len();
    let frame_len = FALCO_SIDE_EFFECT_HEADER_SIZE + payload_len;
    let mut out = Vec::with_capacity(4 + frame_len);

    out.extend_from_slice(&(frame_len as u32).to_le_bytes());
    out.push(FALCO_TYPE_SIDE_EFFECT);
    out.push(0); // flags
    out.extend_from_slice(&[0, 0]); // reserved
    out.extend_from_slice(effect_id.as_bytes());
    out.extend_from_slice(&(payload_len as u32).to_le_bytes());
    out.extend_from_slice(payload);
    out
}

async fn read_publish_ack(stream: &mut UnixStream) -> Result<PublishAckFrame, String> {
    let mut len_buf = [0u8; 4];
    stream
        .read_exact(&mut len_buf)
        .await
        .map_err(|err| format!("failed to read falco ack length: {err}"))?;

    let frame_len = u32::from_le_bytes(len_buf) as usize;
    let mut frame = vec![0u8; frame_len];
    stream
        .read_exact(&mut frame)
        .await
        .map_err(|err| format!("failed to read falco ack frame: {err}"))?;

    parse_publish_ack(&frame)
}

fn parse_publish_ack(data: &[u8]) -> Result<PublishAckFrame, String> {
    if data.len() < FALCO_PUBLISH_ACK_HEADER_SIZE {
        return Err(format!(
            "falco ack frame too short: got {}, need at least {}",
            data.len(),
            FALCO_PUBLISH_ACK_HEADER_SIZE
        ));
    }
    if data[0] != FALCO_TYPE_PUBLISH_ACK {
        return Err(format!(
            "falco invalid frame type: expected 0x{:02x}, got 0x{:02x}",
            FALCO_TYPE_PUBLISH_ACK, data[0]
        ));
    }

    let status = data[1];
    let effect_id = Uuid::from_slice(&data[4..20])
        .map_err(|err| format!("invalid effect_id in falco ack: {err}"))?;

    let error_len = u32::from_le_bytes([data[20], data[21], data[22], data[23]]) as usize;
    let expected_len = FALCO_PUBLISH_ACK_HEADER_SIZE + error_len;
    if data.len() != expected_len {
        return Err(format!(
            "falco ack payload length mismatch: expected {}, got {}",
            expected_len,
            data.len()
        ));
    }

    let error_message = if error_len == 0 {
        String::new()
    } else {
        String::from_utf8(data[24..].to_vec())
            .map_err(|err| format!("falco ack error is not UTF-8: {err}"))?
    };

    Ok(PublishAckFrame {
        effect_id,
        status,
        error_message,
    })
}

#[cfg(test)]
mod tests {
    use super::{
        classify_remote_command_type, format_session_secret_from_key_bytes, idempotency_key,
        parse_publish_ack, should_enforce_over_quota, RemoteCommandType, FALCO_STATUS_SUCCESS,
        FALCO_TYPE_PUBLISH_ACK,
    };
    use crate::app::BillingQuotaSnapshot;
    use crate::itachi::contracts::UmSecretRequestCommand;
    use uuid::Uuid;

    #[test]
    fn idempotency_key_uses_request_and_devices() {
        let request = UmSecretRequestCommand {
            command_type: "um.secret.request.v1".to_string(),
            request_id: "req-1".to_string(),
            session_id: "session-1".to_string(),
            requester_device_id: "requester-1".to_string(),
            target_device_id: "target-1".to_string(),
            requested_at_ms: 123,
        };
        assert_eq!(
            idempotency_key(&request),
            "req-1:requester-1:target-1".to_string()
        );
    }

    #[test]
    fn parse_publish_ack_success() {
        let effect_id = Uuid::new_v4();
        let mut frame = Vec::new();
        frame.push(FALCO_TYPE_PUBLISH_ACK);
        frame.push(FALCO_STATUS_SUCCESS);
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(effect_id.as_bytes());
        frame.extend_from_slice(&0u32.to_le_bytes());

        let parsed = parse_publish_ack(&frame).expect("ack should parse");
        assert_eq!(parsed.effect_id, effect_id);
        assert_eq!(parsed.status, FALCO_STATUS_SUCCESS);
        assert!(parsed.error_message.is_empty());
    }

    #[test]
    fn classify_remote_command_type_supports_gh_pr_commands() {
        assert_eq!(
            classify_remote_command_type("session.create.v1"),
            Some(RemoteCommandType::SessionCreateV1)
        );
        assert_eq!(
            classify_remote_command_type("claude.send.v1"),
            Some(RemoteCommandType::ClaudeSendV1)
        );
        assert_eq!(
            classify_remote_command_type("claude.stop.v1"),
            Some(RemoteCommandType::ClaudeStopV1)
        );
        assert_eq!(
            classify_remote_command_type("git.commit.v1"),
            Some(RemoteCommandType::GitCommitV1)
        );
        assert_eq!(
            classify_remote_command_type("git.push.v1"),
            Some(RemoteCommandType::GitPushV1)
        );
        assert_eq!(
            classify_remote_command_type("gh.pr.create.v1"),
            Some(RemoteCommandType::GhPrCreateV1)
        );
        assert_eq!(
            classify_remote_command_type("gh.pr.view.v1"),
            Some(RemoteCommandType::GhPrViewV1)
        );
        assert_eq!(
            classify_remote_command_type("gh.pr.list.v1"),
            Some(RemoteCommandType::GhPrListV1)
        );
        assert_eq!(
            classify_remote_command_type("gh.pr.checks.v1"),
            Some(RemoteCommandType::GhPrChecksV1)
        );
        assert_eq!(
            classify_remote_command_type("gh.pr.merge.v1"),
            Some(RemoteCommandType::GhPrMergeV1)
        );
        assert_eq!(classify_remote_command_type("gh.pr.unknown.v1"), None);
    }

    #[test]
    fn quota_gate_blocks_when_snapshot_is_fresh_and_over_quota() {
        let snapshot = BillingQuotaSnapshot {
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
            plan: "free".to_string(),
            gateway: "stripe".to_string(),
            period_start: "2026-02-01T00:00:00Z".to_string(),
            period_end: "2026-03-01T00:00:00Z".to_string(),
            enforcement_state: "over_quota".to_string(),
            commands_limit: 100,
            commands_used: 100,
            commands_remaining: 0,
            updated_at: "2026-02-13T00:00:00Z".to_string(),
            fetched_at_ms: 1_000,
        };
        assert!(should_enforce_over_quota(Some(&snapshot), 1_000));
    }

    #[test]
    fn quota_gate_allows_when_snapshot_is_stale() {
        let snapshot = BillingQuotaSnapshot {
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
            plan: "free".to_string(),
            gateway: "stripe".to_string(),
            period_start: "2026-02-01T00:00:00Z".to_string(),
            period_end: "2026-03-01T00:00:00Z".to_string(),
            enforcement_state: "over_quota".to_string(),
            commands_limit: 100,
            commands_used: 100,
            commands_remaining: 0,
            updated_at: "2026-02-13T00:00:00Z".to_string(),
            fetched_at_ms: 1_000,
        };
        assert!(!should_enforce_over_quota(
            Some(&snapshot),
            1_000 + (5 * 60 * 1000) + 1
        ));
    }

    #[test]
    fn quota_gate_allows_when_not_over_quota() {
        let snapshot = BillingQuotaSnapshot {
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
            plan: "free".to_string(),
            gateway: "stripe".to_string(),
            period_start: "2026-02-01T00:00:00Z".to_string(),
            period_end: "2026-03-01T00:00:00Z".to_string(),
            enforcement_state: "ok".to_string(),
            commands_limit: 100,
            commands_used: 12,
            commands_remaining: 88,
            updated_at: "2026-02-13T00:00:00Z".to_string(),
            fetched_at_ms: 1_000,
        };
        assert!(!should_enforce_over_quota(Some(&snapshot), 2_000));
    }

    #[test]
    fn session_secret_format_round_trips_from_key_bytes() {
        let key = vec![0xAB; 32];
        let secret = format_session_secret_from_key_bytes(&key);
        let decoded = daemon_storage::SecretsManager::parse_session_secret(&secret)
            .expect("formatted secret should parse");
        assert_eq!(decoded, key);
    }
}
