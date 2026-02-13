//! Ably hot-path sync worker that publishes encrypted conversation messages via Falco.
//!
//! This worker publishes new messages immediately on enqueue and uses Armin's
//! Ably sync cursor table as a retry sweep for missed/failed messages. Payloads
//! are forwarded to `daemon-falco` over its Unix socket protocol.

use armin::{SessionId, SessionPendingSync, SessionReader, SessionWriter};
use chrono::{DateTime, Utc};
use daemon_config_and_utils::encrypt_conversation_message;
use daemon_storage::SecretsManager;
use serde::Serialize;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tokio::sync::{mpsc, RwLock};
use tokio::time::{interval, Duration};
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::sink::{MessageSyncRequest, MessageSyncer, SyncContext};

/// Falco frame type for side-effect publish requests.
const FALCO_TYPE_SIDE_EFFECT: u8 = 0x03;
/// Falco frame type for publish acknowledgements.
const FALCO_TYPE_PUBLISH_ACK: u8 = 0x04;
/// Falco publish success status.
const FALCO_STATUS_SUCCESS: u8 = 0x01;
/// Falco publish failure status.
const FALCO_STATUS_FAILED: u8 = 0x02;

/// Falco header size for a side-effect frame (excluding length prefix).
const FALCO_SIDE_EFFECT_HEADER_SIZE: usize = 24;
/// Falco header size for a publish ack frame (excluding length prefix).
const FALCO_PUBLISH_ACK_HEADER_SIZE: usize = 24;

/// Event name for session conversation messages.
const CONVERSATION_EVENT_NAME: &str = "conversation.message.v1";
/// Envelope type value used for Falco compatibility logs/routing.
const MESSAGE_APPENDED_TYPE: &str = "message_appended";
/// Symmetric content encryption algorithm identifier.
const CONVERSATION_ENCRYPTION_ALG: &str = "chacha20poly1305";
/// Default queue capacity for enqueue notifications.
const DEFAULT_QUEUE_CAPACITY: usize = 1024;

/// Combined trait for Armin access required by Ably sync.
pub trait AblyArminAccess: SessionWriter + SessionReader {}

impl<T: SessionWriter + SessionReader> AblyArminAccess for T {}

/// Thread-safe Armin handle used by the Ably syncer.
pub type AblyArminHandle = Arc<dyn AblyArminAccess + Send + Sync>;

/// Configuration for Ably hot-sync retry behavior.
#[derive(Debug, Clone)]
pub struct AblySyncConfig {
    /// Maximum number of sessions to scan in one retry sweep.
    pub batch_size: usize,
    /// How often to run retry sweep queries against Armin.
    pub flush_interval: Duration,
    /// Base backoff used for retry_count=1.
    pub backoff_base: Duration,
    /// Maximum backoff cap.
    pub backoff_max: Duration,
    /// Maximum retries before skipping a session.
    pub max_retries: i32,
}

impl Default for AblySyncConfig {
    fn default() -> Self {
        Self {
            batch_size: 50,
            flush_interval: Duration::from_millis(500),
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(300),
            max_retries: 20,
        }
    }
}

/// Ably realtime sync worker with immediate publish + retry sweep.
pub struct AblyRealtimeSyncer {
    config: AblySyncConfig,
    armin: AblyArminHandle,
    context: Arc<RwLock<Option<SyncContext>>>,
    sender: mpsc::Sender<MessageSyncRequest>,
    receiver: Mutex<Option<mpsc::Receiver<MessageSyncRequest>>>,
    secret_cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
    falco_socket_path: PathBuf,
}

impl AblyRealtimeSyncer {
    /// Create a new Ably realtime syncer.
    pub fn new(
        config: AblySyncConfig,
        armin: AblyArminHandle,
        db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
        falco_socket_path: impl Into<PathBuf>,
    ) -> Self {
        let (sender, receiver) = mpsc::channel(DEFAULT_QUEUE_CAPACITY);
        Self {
            config,
            armin,
            context: Arc::new(RwLock::new(None)),
            sender,
            receiver: Mutex::new(Some(receiver)),
            secret_cache: Arc::new(Mutex::new(HashMap::new())),
            db_encryption_key,
            falco_socket_path: falco_socket_path.into(),
        }
    }

    /// Starts the background sync loop.
    ///
    /// Panics if called more than once.
    pub fn start(&self) {
        let mut receiver = self
            .receiver
            .lock()
            .expect("lock poisoned")
            .take()
            .expect("AblyRealtimeSyncer already started");

        let config = self.config.clone();
        let armin = self.armin.clone();
        let context = self.context.clone();
        let secret_cache = self.secret_cache.clone();
        let db_encryption_key = self.db_encryption_key.clone();
        let falco_socket_path = self.falco_socket_path.clone();

        tokio::spawn(async move {
            let mut ticker = interval(config.flush_interval);
            let mut falco_stream: Option<UnixStream> = None;

            loop {
                tokio::select! {
                    maybe_msg = receiver.recv() => {
                        match maybe_msg {
                            Some(msg) => {
                                let session_id_for_log = msg.session_id.clone();
                                let message_id_for_log = msg.message_id.clone();
                                let sequence_number_for_log = msg.sequence_number;
                                if let Err(err) = send_enqueued_message(
                                    &armin,
                                    &context,
                                    &secret_cache,
                                    &db_encryption_key,
                                    &falco_socket_path,
                                    &mut falco_stream,
                                    msg,
                                ).await {
                                    warn!(
                                        session_id = %session_id_for_log,
                                        message_id = %message_id_for_log,
                                        sequence_number = sequence_number_for_log,
                                        error = %err,
                                        "Ably hot-sync message publish failed"
                                    );
                                }
                            }
                            None => break,
                        }
                    }
                    _ = ticker.tick() => {
                        process_retry_sweep(
                            &config,
                            &armin,
                            &context,
                            &secret_cache,
                            &db_encryption_key,
                            &falco_socket_path,
                            &mut falco_stream,
                        ).await;
                    }
                }
            }
        });
    }

    /// Sets the auth/device context used for outbound payload metadata.
    pub async fn set_context(&self, context: SyncContext) {
        let mut guard = self.context.write().await;
        *guard = Some(context);
    }

    /// Clears auth/device context; worker will skip sync while cleared.
    pub async fn clear_context(&self) {
        let mut guard = self.context.write().await;
        *guard = None;
    }
}

impl MessageSyncer for AblyRealtimeSyncer {
    /// Enqueue a notification that new messages are available.
    fn enqueue(&self, request: MessageSyncRequest) {
        if let Err(err) = self.sender.try_send(request) {
            debug!(error = %err, "AblyRealtimeSyncer enqueue failed");
        }
    }
}

#[derive(Debug, Serialize)]
struct FalcoPublishEnvelope<'a, T> {
    #[serde(rename = "type")]
    effect_type: &'a str,
    channel: String,
    event: &'a str,
    payload: T,
}

#[derive(Debug, Serialize)]
struct ConversationPayload {
    schema_version: u8,
    session_id: String,
    message_id: String,
    sequence_number: i64,
    sender_device_id: String,
    created_at_ms: i64,
    encryption_alg: String,
    content_encrypted: String,
    content_nonce: String,
}

#[derive(Debug)]
struct PublishAckFrame {
    effect_id: Uuid,
    status: u8,
    error_message: String,
}

async fn send_enqueued_message(
    armin: &AblyArminHandle,
    context: &Arc<RwLock<Option<SyncContext>>>,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    falco_socket_path: &Path,
    falco_stream: &mut Option<UnixStream>,
    request: MessageSyncRequest,
) -> Result<(), String> {
    let ctx = {
        let guard = context.read().await;
        guard.clone()
    };
    let Some(ctx) = ctx else {
        debug!(
            session_id = %request.session_id,
            message_id = %request.message_id,
            "Ably hot-sync skipping enqueued message (no context)"
        );
        return Ok(());
    };

    let encrypted = encrypt_message(
        armin,
        secret_cache,
        db_encryption_key,
        &request.session_id,
        request.content.as_bytes(),
    )
    .inspect_err(|err| {
        let _ = armin.mark_ably_sync_failed(&SessionId::from_string(&request.session_id), err);
    })?;

    let payload = ConversationPayload {
        schema_version: 1,
        session_id: request.session_id.clone(),
        message_id: request.message_id.clone(),
        sequence_number: request.sequence_number,
        sender_device_id: ctx.device_id,
        created_at_ms: Utc::now().timestamp_millis(),
        encryption_alg: CONVERSATION_ENCRYPTION_ALG.to_string(),
        content_encrypted: encrypted.0,
        content_nonce: encrypted.1,
    };

    let envelope = FalcoPublishEnvelope {
        effect_type: MESSAGE_APPENDED_TYPE,
        channel: session_conversation_channel(&request.session_id),
        event: CONVERSATION_EVENT_NAME,
        payload,
    };

    let bytes =
        serde_json::to_vec(&envelope).map_err(|err| format!("serialize payload: {}", err))?;
    publish_via_falco(falco_stream, falco_socket_path, &bytes)
        .await
        .inspect_err(|err| {
            let _ = armin.mark_ably_sync_failed(&SessionId::from_string(&request.session_id), err);
        })?;

    let session_id = SessionId::from_string(&request.session_id);
    let _ = armin.mark_ably_sync_success(&session_id, request.sequence_number);
    info!(
        session_id = %request.session_id,
        message_id = %request.message_id,
        sequence_number = request.sequence_number,
        channel = %session_conversation_channel(&request.session_id),
        event = CONVERSATION_EVENT_NAME,
        "Ably hot-sync message published"
    );
    #[cfg(debug_assertions)]
    info!(
        session_id = %request.session_id,
        size_kb = format!("{:.2}", bytes.len() as f64 / 1024.0),
        "Ably hot-sync message size"
    );

    Ok(())
}

async fn process_retry_sweep(
    config: &AblySyncConfig,
    armin: &AblyArminHandle,
    context: &Arc<RwLock<Option<SyncContext>>>,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    falco_socket_path: &Path,
    falco_stream: &mut Option<UnixStream>,
) {
    let sessions_to_sync = match armin.get_sessions_pending_ably_sync(config.batch_size) {
        Ok(sessions) => sessions,
        Err(err) => {
            warn!(error = %err, "Ably hot-sync failed to query pending sessions");
            return;
        }
    };

    let now = Utc::now();
    for session_pending in sessions_to_sync {
        if session_pending.retry_count > config.max_retries {
            debug!(
                session_id = %session_pending.session_id.as_str(),
                retry_count = session_pending.retry_count,
                max_retries = config.max_retries,
                "Skipping Ably sync (max retries exceeded)"
            );
            continue;
        }

        if !is_session_due(
            session_pending.last_attempt_at,
            session_pending.retry_count,
            now,
            config,
        ) {
            continue;
        }

        let session_id_for_log = session_pending.session_id.as_str().to_string();
        let retry_count = session_pending.retry_count;
        if let Err(err) = send_session_batch(
            armin,
            context,
            secret_cache,
            db_encryption_key,
            falco_socket_path,
            falco_stream,
            session_pending,
        )
        .await
        {
            warn!(
                session_id = %session_id_for_log,
                retry_count = retry_count,
                error = %err,
                "Ably hot-sync retry sweep failed"
            );
        }
    }
}

async fn send_session_batch(
    armin: &AblyArminHandle,
    context: &Arc<RwLock<Option<SyncContext>>>,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    falco_socket_path: &Path,
    falco_stream: &mut Option<UnixStream>,
    session_pending: SessionPendingSync,
) -> Result<(), String> {
    let ctx = {
        let guard = context.read().await;
        guard.clone()
    };
    let Some(ctx) = ctx else {
        debug!("Ably hot-sync skipping batch (no context)");
        return Ok(());
    };

    if session_pending.messages.is_empty() {
        return Ok(());
    }

    let session_id = &session_pending.session_id;
    for message in &session_pending.messages {
        let encrypted = match encrypt_message(
            armin,
            secret_cache,
            db_encryption_key,
            session_id.as_str(),
            message.content.as_bytes(),
        ) {
            Ok(v) => v,
            Err(err) => {
                let _ = armin.mark_ably_sync_failed(session_id, &err);
                return Err(err);
            }
        };

        let payload = ConversationPayload {
            schema_version: 1,
            session_id: session_id.as_str().to_string(),
            message_id: message.message_id.as_str().to_string(),
            sequence_number: message.sequence_number,
            sender_device_id: ctx.device_id.clone(),
            created_at_ms: Utc::now().timestamp_millis(),
            encryption_alg: CONVERSATION_ENCRYPTION_ALG.to_string(),
            content_encrypted: encrypted.0,
            content_nonce: encrypted.1,
        };

        let envelope = FalcoPublishEnvelope {
            effect_type: MESSAGE_APPENDED_TYPE,
            channel: session_conversation_channel(session_id.as_str()),
            event: CONVERSATION_EVENT_NAME,
            payload,
        };

        let bytes =
            serde_json::to_vec(&envelope).map_err(|err| format!("serialize payload: {}", err))?;

        if let Err(err) = publish_via_falco(falco_stream, falco_socket_path, &bytes).await {
            let _ = armin.mark_ably_sync_failed(session_id, &err);
            return Err(err);
        }

        info!(
            session_id = %session_id.as_str(),
            message_id = %message.message_id.as_str(),
            sequence_number = message.sequence_number,
            channel = %session_conversation_channel(session_id.as_str()),
            event = CONVERSATION_EVENT_NAME,
            "Ably hot-sync message published"
        );
        #[cfg(debug_assertions)]
        info!(
            session_id = %session_id.as_str(),
            size_kb = format!("{:.2}", bytes.len() as f64 / 1024.0),
            "Ably hot-sync message size"
        );
        let _ = armin.mark_ably_sync_success(session_id, message.sequence_number);
    }

    Ok(())
}

async fn publish_via_falco(
    falco_stream: &mut Option<UnixStream>,
    falco_socket_path: &Path,
    json_payload: &[u8],
) -> Result<(), String> {
    let effect_id = Uuid::new_v4();
    let frame = encode_side_effect_frame(effect_id, json_payload);

    let stream = ensure_falco_connected(falco_stream, falco_socket_path).await?;
    if let Err(err) = stream.write_all(&frame).await {
        *falco_stream = None;
        return Err(format!("falco write failed: {}", err));
    }

    let ack = match read_publish_ack(stream).await {
        Ok(ack) => ack,
        Err(err) => {
            *falco_stream = None;
            return Err(err);
        }
    };

    if ack.effect_id != effect_id {
        *falco_stream = None;
        return Err(format!(
            "falco ack mismatch: expected {}, got {}",
            effect_id, ack.effect_id
        ));
    }

    match ack.status {
        FALCO_STATUS_SUCCESS => Ok(()),
        FALCO_STATUS_FAILED => Err(format!(
            "falco publish failed: {}",
            if ack.error_message.is_empty() {
                "unknown error"
            } else {
                &ack.error_message
            }
        )),
        status => {
            *falco_stream = None;
            Err(format!("falco invalid status: 0x{status:02x}"))
        }
    }
}

async fn ensure_falco_connected<'a>(
    falco_stream: &'a mut Option<UnixStream>,
    falco_socket_path: &Path,
) -> Result<&'a mut UnixStream, String> {
    if falco_stream.is_none() {
        let stream = UnixStream::connect(falco_socket_path)
            .await
            .map_err(|err| {
                format!(
                    "failed to connect to falco socket {}: {}",
                    falco_socket_path.display(),
                    err
                )
            })?;
        *falco_stream = Some(stream);
    }
    Ok(falco_stream.as_mut().expect("stream set above"))
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
        .map_err(|err| format!("failed to read falco frame length: {}", err))?;

    let frame_len = u32::from_le_bytes(len_buf) as usize;
    let mut frame = vec![0u8; frame_len];
    stream
        .read_exact(&mut frame)
        .await
        .map_err(|err| format!("failed to read falco frame body: {}", err))?;

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
        .map_err(|err| format!("falco invalid effect id in ack: {}", err))?;

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
            .map_err(|err| format!("falco ack error message is not valid UTF-8: {}", err))?
    };

    Ok(PublishAckFrame {
        effect_id,
        status,
        error_message,
    })
}

fn session_conversation_channel(session_id: &str) -> String {
    format!("session:{session_id}:conversation")
}

fn encrypt_message(
    armin: &AblyArminHandle,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    session_id: &str,
    plaintext: &[u8],
) -> Result<(String, String), String> {
    let key = get_session_secret_key(armin, secret_cache, db_encryption_key, session_id)?;
    let encrypted = encrypt_conversation_message(&key, plaintext).map_err(|err| err.to_string())?;
    Ok((encrypted.content_encrypted_b64, encrypted.content_nonce_b64))
}

fn get_session_secret_key(
    armin: &AblyArminHandle,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    session_id: &str,
) -> Result<Vec<u8>, String> {
    if let Some(existing) = secret_cache
        .lock()
        .expect("lock poisoned")
        .get(session_id)
        .cloned()
    {
        return Ok(existing);
    }

    let db_key = db_encryption_key
        .lock()
        .expect("lock poisoned")
        .to_owned()
        .ok_or_else(|| "missing database encryption key".to_string())?;

    let session_secret = armin
        .get_session_secret(&SessionId::from_string(session_id))
        .map_err(|err| format!("failed to get session secret: {}", err))?
        .ok_or_else(|| "missing session secret".to_string())?;

    let plaintext = daemon_database::decrypt_content(
        &db_key,
        &session_secret.nonce,
        &session_secret.encrypted_secret,
    )
    .map_err(|err| {
        format!(
            "failed to decrypt session secret for session {}: {} (this usually indicates a stale database encryption key or corrupted session secret record)",
            session_id, err
        )
    })?;

    let secret = String::from_utf8(plaintext)
        .map_err(|err| format!("session secret is not UTF-8: {}", err))?;
    let key = SecretsManager::parse_session_secret(&secret).map_err(|err| {
        format!(
            "invalid session secret format for session {}: {}",
            session_id, err
        )
    })?;

    secret_cache
        .lock()
        .expect("lock poisoned")
        .insert(session_id.to_string(), key.clone());

    Ok(key)
}

fn is_session_due(
    last_attempt_at: Option<DateTime<Utc>>,
    retry_count: i32,
    now: DateTime<Utc>,
    config: &AblySyncConfig,
) -> bool {
    let Some(last_attempt) = last_attempt_at else {
        return true;
    };

    let backoff = compute_backoff(retry_count, config);
    now >= last_attempt + backoff
}

fn compute_backoff(retry_count: i32, config: &AblySyncConfig) -> chrono::Duration {
    if retry_count <= 0 {
        return chrono::Duration::zero();
    }

    let base_ms = config.backoff_base.as_millis() as u64;
    let max_ms = config.backoff_max.as_millis() as u64;
    let shift = retry_count.saturating_sub(1) as u32;
    let multiplier = 1u64.checked_shl(shift).unwrap_or(u64::MAX);
    let delay_ms = base_ms.saturating_mul(multiplier).min(max_ms);

    chrono::Duration::milliseconds(delay_ms as i64)
}

#[cfg(test)]
mod tests {
    use super::*;

    // =========================================================================
    // session_conversation_channel
    // =========================================================================

    #[test]
    fn conversation_channel_format() {
        assert_eq!(
            session_conversation_channel("abc-123"),
            "session:abc-123:conversation"
        );
    }

    #[test]
    fn conversation_channel_with_uuid() {
        let id = "550e8400-e29b-41d4-a716-446655440000";
        assert_eq!(
            session_conversation_channel(id),
            format!("session:{}:conversation", id)
        );
    }

    // =========================================================================
    // encode_side_effect_frame
    // =========================================================================

    #[test]
    fn encode_side_effect_frame_structure() {
        let effect_id = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let payload = b"hello";
        let frame = encode_side_effect_frame(effect_id, payload);

        // 4 bytes length prefix + 24 header + 5 payload = 33
        assert_eq!(
            frame.len(),
            4 + FALCO_SIDE_EFFECT_HEADER_SIZE + payload.len()
        );

        // Length prefix (LE u32) = 24 + 5 = 29
        let frame_len = u32::from_le_bytes([frame[0], frame[1], frame[2], frame[3]]) as usize;
        assert_eq!(frame_len, FALCO_SIDE_EFFECT_HEADER_SIZE + payload.len());

        // Type byte
        assert_eq!(frame[4], FALCO_TYPE_SIDE_EFFECT);
        // Flags byte
        assert_eq!(frame[5], 0);
        // Reserved bytes
        assert_eq!(frame[6], 0);
        assert_eq!(frame[7], 0);

        // UUID (16 bytes at offset 8..24)
        let parsed_id = Uuid::from_slice(&frame[8..24]).unwrap();
        assert_eq!(parsed_id, effect_id);

        // Payload length (LE u32 at offset 24..28)
        let payload_len = u32::from_le_bytes([frame[24], frame[25], frame[26], frame[27]]) as usize;
        assert_eq!(payload_len, payload.len());

        // Payload bytes
        assert_eq!(&frame[28..], payload);
    }

    #[test]
    fn encode_side_effect_frame_empty_payload() {
        let effect_id = Uuid::new_v4();
        let frame = encode_side_effect_frame(effect_id, &[]);

        assert_eq!(frame.len(), 4 + FALCO_SIDE_EFFECT_HEADER_SIZE);

        // Payload length should be 0
        let payload_len = u32::from_le_bytes([frame[24], frame[25], frame[26], frame[27]]) as usize;
        assert_eq!(payload_len, 0);
    }

    // =========================================================================
    // parse_publish_ack
    // =========================================================================

    #[test]
    fn parse_publish_ack_success() {
        let effect_id = Uuid::new_v4();
        let mut frame = Vec::new();
        frame.push(FALCO_TYPE_PUBLISH_ACK);
        frame.push(FALCO_STATUS_SUCCESS);
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(effect_id.as_bytes());
        frame.extend_from_slice(&0u32.to_le_bytes());

        let ack = parse_publish_ack(&frame).expect("ack should parse");
        assert_eq!(ack.effect_id, effect_id);
        assert_eq!(ack.status, FALCO_STATUS_SUCCESS);
        assert!(ack.error_message.is_empty());
    }

    #[test]
    fn parse_publish_ack_with_error_message() {
        let effect_id = Uuid::new_v4();
        let error_msg = "publish timeout";
        let error_bytes = error_msg.as_bytes();

        let mut frame = Vec::new();
        frame.push(FALCO_TYPE_PUBLISH_ACK);
        frame.push(FALCO_STATUS_FAILED);
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(effect_id.as_bytes());
        frame.extend_from_slice(&(error_bytes.len() as u32).to_le_bytes());
        frame.extend_from_slice(error_bytes);

        let ack = parse_publish_ack(&frame).expect("ack should parse");
        assert_eq!(ack.effect_id, effect_id);
        assert_eq!(ack.status, FALCO_STATUS_FAILED);
        assert_eq!(ack.error_message, "publish timeout");
    }

    #[test]
    fn parse_publish_ack_frame_too_short() {
        let frame = vec![0u8; 10]; // Less than FALCO_PUBLISH_ACK_HEADER_SIZE (24)
        let err = parse_publish_ack(&frame).unwrap_err();
        assert!(err.contains("too short"));
    }

    #[test]
    fn parse_publish_ack_wrong_frame_type() {
        let effect_id = Uuid::new_v4();
        let mut frame = Vec::new();
        frame.push(FALCO_TYPE_SIDE_EFFECT); // wrong type
        frame.push(FALCO_STATUS_SUCCESS);
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(effect_id.as_bytes());
        frame.extend_from_slice(&0u32.to_le_bytes());

        let err = parse_publish_ack(&frame).unwrap_err();
        assert!(err.contains("invalid frame type"));
    }

    #[test]
    fn parse_publish_ack_payload_length_mismatch() {
        let effect_id = Uuid::new_v4();
        let mut frame = Vec::new();
        frame.push(FALCO_TYPE_PUBLISH_ACK);
        frame.push(FALCO_STATUS_SUCCESS);
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(effect_id.as_bytes());
        // Claim 100 bytes of error message, but provide none
        frame.extend_from_slice(&100u32.to_le_bytes());

        let err = parse_publish_ack(&frame).unwrap_err();
        assert!(err.contains("length mismatch"));
    }

    #[test]
    fn parse_publish_ack_invalid_utf8_error() {
        let effect_id = Uuid::new_v4();
        let bad_utf8: &[u8] = &[0xFF, 0xFE, 0xFD];

        let mut frame = Vec::new();
        frame.push(FALCO_TYPE_PUBLISH_ACK);
        frame.push(FALCO_STATUS_FAILED);
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(effect_id.as_bytes());
        frame.extend_from_slice(&(bad_utf8.len() as u32).to_le_bytes());
        frame.extend_from_slice(bad_utf8);

        let err = parse_publish_ack(&frame).unwrap_err();
        assert!(err.contains("not valid UTF-8"));
    }

    #[test]
    fn parse_publish_ack_exactly_header_size_no_error() {
        let effect_id = Uuid::new_v4();
        let mut frame = Vec::new();
        frame.push(FALCO_TYPE_PUBLISH_ACK);
        frame.push(FALCO_STATUS_SUCCESS);
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(effect_id.as_bytes());
        frame.extend_from_slice(&0u32.to_le_bytes()); // 0 error bytes

        let ack = parse_publish_ack(&frame).unwrap();
        assert_eq!(ack.effect_id, effect_id);
        assert!(ack.error_message.is_empty());
    }

    // =========================================================================
    // compute_backoff
    // =========================================================================

    #[test]
    fn compute_backoff_caps_and_grows() {
        let config = AblySyncConfig {
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(10),
            ..AblySyncConfig::default()
        };

        assert_eq!(compute_backoff(0, &config), chrono::Duration::zero());
        assert_eq!(compute_backoff(1, &config), chrono::Duration::seconds(2));
        assert_eq!(compute_backoff(2, &config), chrono::Duration::seconds(4));
        assert_eq!(compute_backoff(3, &config), chrono::Duration::seconds(8));
        assert_eq!(compute_backoff(4, &config), chrono::Duration::seconds(10));
        assert_eq!(compute_backoff(10, &config), chrono::Duration::seconds(10));
    }

    #[test]
    fn compute_backoff_negative_retry_returns_zero() {
        let config = AblySyncConfig::default();
        assert_eq!(compute_backoff(-1, &config), chrono::Duration::zero());
        assert_eq!(compute_backoff(-100, &config), chrono::Duration::zero());
    }

    #[test]
    fn compute_backoff_very_large_retry_caps_at_max() {
        let config = AblySyncConfig {
            backoff_base: Duration::from_secs(1),
            backoff_max: Duration::from_secs(300),
            ..AblySyncConfig::default()
        };
        // Extremely large retry count should not overflow, should cap at max
        let result = compute_backoff(1000, &config);
        assert_eq!(result, chrono::Duration::seconds(300));
    }

    // =========================================================================
    // is_session_due
    // =========================================================================

    #[test]
    fn is_session_due_no_last_attempt_returns_true() {
        let config = AblySyncConfig::default();
        assert!(is_session_due(None, 0, Utc::now(), &config));
    }

    #[test]
    fn is_session_due_recent_attempt_returns_false() {
        let config = AblySyncConfig {
            backoff_base: Duration::from_secs(60),
            backoff_max: Duration::from_secs(300),
            ..AblySyncConfig::default()
        };
        let now = Utc::now();
        // Last attempt was 1 second ago, backoff for retry_count=1 is 60s
        let last_attempt = now - chrono::Duration::seconds(1);
        assert!(!is_session_due(Some(last_attempt), 1, now, &config));
    }

    #[test]
    fn is_session_due_old_attempt_returns_true() {
        let config = AblySyncConfig {
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(300),
            ..AblySyncConfig::default()
        };
        let now = Utc::now();
        // Last attempt was 10 seconds ago, backoff for retry_count=1 is 2s
        let last_attempt = now - chrono::Duration::seconds(10);
        assert!(is_session_due(Some(last_attempt), 1, now, &config));
    }

    #[test]
    fn is_session_due_zero_retry_always_due() {
        let config = AblySyncConfig::default();
        let now = Utc::now();
        // retry_count=0 means backoff=0, so always due
        let last_attempt = now - chrono::Duration::milliseconds(1);
        assert!(is_session_due(Some(last_attempt), 0, now, &config));
    }

    // =========================================================================
    // AblySyncConfig defaults
    // =========================================================================

    #[test]
    fn ably_sync_config_defaults() {
        let config = AblySyncConfig::default();
        assert_eq!(config.batch_size, 50);
        assert_eq!(config.flush_interval, Duration::from_millis(500));
        assert_eq!(config.backoff_base, Duration::from_secs(2));
        assert_eq!(config.backoff_max, Duration::from_secs(300));
        assert_eq!(config.max_retries, 20);
    }

    // =========================================================================
    // FalcoPublishEnvelope / ConversationPayload serialization
    // =========================================================================

    #[test]
    fn falco_envelope_serialization() {
        let payload = ConversationPayload {
            schema_version: 1,
            session_id: "sess-1".to_string(),
            message_id: "msg-1".to_string(),
            sequence_number: 5,
            sender_device_id: "device-1".to_string(),
            created_at_ms: 1700000000000,
            encryption_alg: CONVERSATION_ENCRYPTION_ALG.to_string(),
            content_encrypted: "encrypted".to_string(),
            content_nonce: "nonce".to_string(),
        };

        let envelope = FalcoPublishEnvelope {
            effect_type: MESSAGE_APPENDED_TYPE,
            channel: session_conversation_channel("sess-1"),
            event: CONVERSATION_EVENT_NAME,
            payload,
        };

        let json = serde_json::to_value(&envelope).unwrap();
        assert_eq!(json["type"], MESSAGE_APPENDED_TYPE);
        assert_eq!(json["channel"], "session:sess-1:conversation");
        assert_eq!(json["event"], CONVERSATION_EVENT_NAME);
        assert_eq!(json["payload"]["schema_version"], 1);
        assert_eq!(json["payload"]["session_id"], "sess-1");
        assert_eq!(json["payload"]["message_id"], "msg-1");
        assert_eq!(json["payload"]["sequence_number"], 5);
        assert_eq!(json["payload"]["sender_device_id"], "device-1");
        assert_eq!(json["payload"]["encryption_alg"], "chacha20poly1305");
        assert_eq!(json["payload"]["content_encrypted"], "encrypted");
        assert_eq!(json["payload"]["content_nonce"], "nonce");
    }

    #[test]
    fn falco_envelope_type_field_renamed() {
        let envelope = FalcoPublishEnvelope {
            effect_type: "test_type",
            channel: "ch".to_string(),
            event: "ev",
            payload: serde_json::json!({}),
        };
        let json = serde_json::to_value(&envelope).unwrap();
        // Verify #[serde(rename = "type")] works
        assert!(json.get("type").is_some());
        assert!(json.get("effect_type").is_none());
    }
}
