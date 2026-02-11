use crate::app::DaemonState;
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
use armin::SessionReader;
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use daemon_config_and_utils::encrypt_for_device;
use std::path::Path;
use std::time::Instant;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tokio::time::{sleep, Duration};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

const NONCE_SIZE: usize = 12;
const MIN_CIPHERTEXT_WITH_TAG_SIZE: usize = 16;

const FALCO_TYPE_SIDE_EFFECT: u8 = 0x03;
const FALCO_TYPE_PUBLISH_ACK: u8 = 0x04;
const FALCO_STATUS_SUCCESS: u8 = 0x01;
const FALCO_STATUS_FAILED: u8 = 0x02;
const FALCO_SIDE_EFFECT_HEADER_SIZE: usize = 24;
const FALCO_PUBLISH_ACK_HEADER_SIZE: usize = 24;

const FALCO_RETRY_ATTEMPTS: usize = 3;
const FALCO_BACKOFF_BASE_MS: u64 = 200;

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
    let response = match envelope.command_type.as_str() {
        // Command routing will be wired in Task 5
        _ => RemoteCommandResponse::error(
            envelope.request_id.clone(),
            envelope.command_type.clone(),
            "not_implemented",
            format!("command type {} is not yet implemented", envelope.command_type),
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
    let db_key = state
        .db_encryption_key
        .lock()
        .unwrap()
        .to_owned()
        .ok_or_else(|| "missing database encryption key".to_string())?;

    let session_secret = state
        .armin
        .get_session_secret(&armin::SessionId::from_string(session_id))
        .map_err(|err| format!("failed to get session secret: {err}"))?
        .ok_or_else(|| "session secret not found".to_string())?;

    let plaintext = daemon_database::decrypt_content(
        &db_key,
        &session_secret.nonce,
        &session_secret.encrypted_secret,
    )
    .map_err(|err| format!("failed to decrypt session secret: {err}"))?;

    String::from_utf8(plaintext).map_err(|err| format!("session secret is not UTF-8: {err}"))
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
    use super::{idempotency_key, parse_publish_ack, FALCO_STATUS_SUCCESS, FALCO_TYPE_PUBLISH_ACK};
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
}
