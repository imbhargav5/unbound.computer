//! Levi: Supabase message sync worker.
//!
//! Batches message writes to Supabase, encrypts content, and tracks retries via
//! SQLite outbox entries.

mod session_sync;

pub use session_sync::{SessionSyncService, SyncError, SyncResult};

use armin::{MessageId, PendingSupabaseMessage, SessionId, SessionReader, SessionWriter};
use base64::Engine;
use chrono::{DateTime, Utc};
use daemon_database::{encrypt_content, generate_nonce};
use daemon_storage::SecretsManager;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, RwLock};
use tokio::time::{interval, Duration};
use toshinori::{MessageSyncRequest, MessageSyncer, MessageUpsert, SupabaseClient, SyncContext};
use tracing::{debug, warn};

const BASE64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;
const DEFAULT_ROLE: &str = "assistant";
const DEFAULT_QUEUE_CAPACITY: usize = 1024;

/// Combined trait for Armin access.
pub trait ArminAccess: SessionWriter + SessionReader {}

impl<T: SessionWriter + SessionReader> ArminAccess for T {}

/// Handle type for Armin access.
pub type ArminHandle = Arc<dyn ArminAccess + Send + Sync>;

/// Configuration for Levi batching and backoff.
#[derive(Debug, Clone)]
pub struct LeviConfig {
    pub batch_size: usize,
    pub flush_interval: Duration,
    pub backoff_base: Duration,
    pub backoff_max: Duration,
}

impl Default for LeviConfig {
    fn default() -> Self {
        Self {
            batch_size: 50,
            flush_interval: Duration::from_millis(500),
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(300),
        }
    }
}

/// Levi message sync worker.
pub struct Levi {
    config: LeviConfig,
    client: SupabaseClient,
    armin: ArminHandle,
    context: Arc<RwLock<Option<SyncContext>>>,
    sender: mpsc::Sender<MessageSyncRequest>,
    receiver: Mutex<Option<mpsc::Receiver<MessageSyncRequest>>>,
    secret_cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
}

impl Levi {
    pub fn new(
        config: LeviConfig,
        api_url: impl Into<String>,
        anon_key: impl Into<String>,
        armin: ArminHandle,
        db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
    ) -> Self {
        let (sender, receiver) = mpsc::channel(DEFAULT_QUEUE_CAPACITY);
        Self {
            config,
            client: SupabaseClient::new(api_url, anon_key),
            armin,
            context: Arc::new(RwLock::new(None)),
            sender,
            receiver: Mutex::new(Some(receiver)),
            secret_cache: Arc::new(Mutex::new(HashMap::new())),
            db_encryption_key,
        }
    }

    /// Start the worker loop.
    pub fn start(&self) {
        let mut receiver = self
            .receiver
            .lock()
            .expect("lock poisoned")
            .take()
            .expect("Levi already started");

        let config = self.config.clone();
        let client = self.client.clone();
        let armin = self.armin.clone();
        let context = self.context.clone();
        let secret_cache = self.secret_cache.clone();
        let db_encryption_key = self.db_encryption_key.clone();

        tokio::spawn(async move {
            let mut buffer: Vec<QueuedMessage> = Vec::new();
            let mut buffer_ids: HashSet<String> = HashSet::new();
            let mut ticker = interval(config.flush_interval);

            loop {
                let mut flush_now = false;

                tokio::select! {
                    maybe_msg = receiver.recv() => {
                        match maybe_msg {
                            Some(msg) => {
                                if buffer_ids.insert(msg.message_id.clone()) {
                                    buffer.push(QueuedMessage::from_request(msg));
                                }
                                if buffer.len() >= config.batch_size {
                                    flush_now = true;
                                }
                            }
                            None => break,
                        }
                    }
                    _ = ticker.tick() => {
                        flush_now = true;
                    }
                }

                if flush_now {
                    fill_from_outbox(&armin, &config, &mut buffer, &mut buffer_ids);

                    if buffer.is_empty() {
                        continue;
                    }

                    let batch_size = std::cmp::min(buffer.len(), config.batch_size);
                    let batch: Vec<QueuedMessage> = buffer.drain(..batch_size).collect();
                    for msg in &batch {
                        buffer_ids.remove(&msg.message_id);
                    }

                    if let Err(err) = send_batch(
                        &client,
                        &armin,
                        &context,
                        &secret_cache,
                        &db_encryption_key,
                        batch,
                    )
                    .await
                    {
                        warn!(error = %err, "Levi batch failed");
                    }
                }
            }
        });
    }

    /// Set sync context (access token).
    pub async fn set_context(&self, context: SyncContext) {
        let mut guard = self.context.write().await;
        *guard = Some(context);
    }

    /// Clear sync context.
    pub async fn clear_context(&self) {
        let mut guard = self.context.write().await;
        *guard = None;
    }
}

impl MessageSyncer for Levi {
    fn enqueue(&self, request: MessageSyncRequest) {
        if let Err(err) = self.sender.try_send(request) {
            debug!(error = %err, "Levi enqueue failed");
        }
    }
}

#[derive(Debug, Clone)]
struct QueuedMessage {
    message_id: String,
    session_id: String,
    sequence_number: i64,
    content: String,
}

impl QueuedMessage {
    fn from_request(req: MessageSyncRequest) -> Self {
        Self {
            message_id: req.message_id,
            session_id: req.session_id,
            sequence_number: req.sequence_number,
            content: req.content,
        }
    }

    fn from_pending(pending: PendingSupabaseMessage) -> Self {
        Self {
            message_id: pending.message_id.as_str().to_string(),
            session_id: pending.session_id.as_str().to_string(),
            sequence_number: pending.sequence_number,
            content: pending.content,
        }
    }
}

fn fill_from_outbox(
    armin: &ArminHandle,
    config: &LeviConfig,
    buffer: &mut Vec<QueuedMessage>,
    buffer_ids: &mut HashSet<String>,
) {
    if buffer.len() >= config.batch_size {
        return;
    }

    let pending = armin.get_pending_supabase_messages(config.batch_size * 2);
    let now = Utc::now();

    for entry in pending {
        if buffer.len() >= config.batch_size {
            break;
        }
        let message_id = entry.message_id.as_str().to_string();
        if buffer_ids.contains(&message_id) {
            continue;
        }
        if !is_due(entry.last_attempt_at, entry.retry_count, now, config) {
            continue;
        }
        buffer_ids.insert(message_id);
        buffer.push(QueuedMessage::from_pending(entry));
    }
}

async fn send_batch(
    client: &SupabaseClient,
    armin: &ArminHandle,
    context: &Arc<RwLock<Option<SyncContext>>>,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    batch: Vec<QueuedMessage>,
) -> Result<(), String> {
    let ctx = {
        let guard = context.read().await;
        guard.clone()
    };
    let Some(ctx) = ctx else {
        debug!("Levi: skipping batch (no context)");
        return Ok(());
    };

    let mut payloads: Vec<MessageUpsert> = Vec::new();
    let mut send_ids: Vec<MessageId> = Vec::new();

    for message in &batch {
        match encrypt_message(
            armin,
            secret_cache,
            db_encryption_key,
            &message.session_id,
            message.content.as_bytes(),
        ) {
            Ok((cipher_b64, nonce_b64)) => {
                payloads.push(MessageUpsert {
                    session_id: message.session_id.clone(),
                    sequence_number: message.sequence_number,
                    role: DEFAULT_ROLE.to_string(),
                    content_encrypted: Some(cipher_b64),
                    content_nonce: Some(nonce_b64),
                });
                send_ids.push(MessageId::from_string(message.message_id.clone()));
            }
            Err(err) => {
                let id = MessageId::from_string(message.message_id.clone());
                armin.mark_supabase_messages_failed(&[id], &err);
            }
        }
    }

    if payloads.is_empty() {
        return Ok(());
    }

    match client.upsert_messages_batch(&payloads, &ctx.access_token).await {
        Ok(()) => {
            armin.mark_supabase_messages_sent(&send_ids);
            armin.delete_supabase_message_outbox(&send_ids);
            Ok(())
        }
        Err(err) => {
            let error = err.to_string();
            armin.mark_supabase_messages_failed(&send_ids, &error);
            Err(error)
        }
    }
}

fn encrypt_message(
    armin: &ArminHandle,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    session_id: &str,
    plaintext: &[u8],
) -> Result<(String, String), String> {
    let key = get_session_secret_key(armin, secret_cache, db_encryption_key, session_id)?;
    let nonce = generate_nonce();
    let ciphertext = encrypt_content(&key, &nonce, plaintext).map_err(|e| e.to_string())?;

    Ok((BASE64.encode(ciphertext), BASE64.encode(nonce)))
}

fn get_session_secret_key(
    armin: &ArminHandle,
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
        .clone()
        .ok_or_else(|| "missing database encryption key".to_string())?;

    let session_secret = armin
        .get_session_secret(&SessionId::from_string(session_id))
        .ok_or_else(|| "missing session secret".to_string())?;

    let plaintext = daemon_database::decrypt_content(
        &db_key,
        &session_secret.nonce,
        &session_secret.encrypted_secret,
    )
    .map_err(|e| e.to_string())?;

    let secret_str = String::from_utf8(plaintext).map_err(|e| e.to_string())?;
    let key = SecretsManager::parse_session_secret(&secret_str).map_err(|e| e.to_string())?;

    secret_cache
        .lock()
        .expect("lock poisoned")
        .insert(session_id.to_string(), key.clone());

    Ok(key)
}

fn is_due(
    last_attempt_at: Option<DateTime<Utc>>,
    retry_count: i32,
    now: DateTime<Utc>,
    config: &LeviConfig,
) -> bool {
    let Some(last_attempt) = last_attempt_at else {
        return true;
    };

    let backoff = compute_backoff(retry_count, config);
    now >= last_attempt + backoff
}

fn compute_backoff(retry_count: i32, config: &LeviConfig) -> chrono::Duration {
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
    use armin::{RecordingSink, Armin, NewMessage, NewSessionSecret};
    use daemon_database::{encrypt_content, generate_nonce};

    fn setup_armin_with_secret() -> (ArminHandle, SessionId, Arc<Mutex<Option<[u8; 32]>>>) {
        let sink = RecordingSink::new();
        let armin = Arc::new(Armin::in_memory(sink).unwrap());
        let session_id = armin.create_session();

        let session_secret = SecretsManager::generate_session_secret();
        let db_key = [42u8; 32];
        let nonce = generate_nonce();
        let encrypted = encrypt_content(&db_key, &nonce, session_secret.as_bytes()).unwrap();

        armin.set_session_secret(NewSessionSecret {
            session_id: session_id.clone(),
            encrypted_secret: encrypted,
            nonce: nonce.to_vec(),
        });

        (armin as ArminHandle, session_id, Arc::new(Mutex::new(Some(db_key))))
    }

    #[test]
    fn compute_backoff_caps_and_grows() {
        let config = LeviConfig {
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(10),
            ..LeviConfig::default()
        };

        assert_eq!(compute_backoff(0, &config), chrono::Duration::zero());
        assert_eq!(compute_backoff(1, &config), chrono::Duration::seconds(2));
        assert_eq!(compute_backoff(2, &config), chrono::Duration::seconds(4));
        assert_eq!(compute_backoff(3, &config), chrono::Duration::seconds(8));
        assert_eq!(compute_backoff(4, &config), chrono::Duration::seconds(10));
        assert_eq!(compute_backoff(10, &config), chrono::Duration::seconds(10));
    }

    #[test]
    fn is_due_respects_backoff() {
        let config = LeviConfig {
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(10),
            ..LeviConfig::default()
        };

        let now = Utc::now();
        assert!(is_due(None, 0, now, &config));

        let last_attempt = now;
        assert!(!is_due(Some(last_attempt), 1, now, &config));
        assert!(is_due(Some(last_attempt), 1, now + chrono::Duration::seconds(3), &config));
    }

    #[test]
    fn encrypt_message_caches_secret() {
        let (armin, session_id, db_key) = setup_armin_with_secret();
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let result = encrypt_message(
            &armin,
            &cache,
            &db_key,
            session_id.as_str(),
            b"hello",
        );
        assert!(result.is_ok());

        let cached = cache.lock().unwrap();
        assert!(cached.contains_key(session_id.as_str()));
    }

    #[test]
    fn fill_from_outbox_skips_not_due() {
        let (armin, session_id, _db_key) = setup_armin_with_secret();

        let msg1 = armin.append(&session_id, NewMessage { content: "first".to_string() });
        let msg2 = armin.append(&session_id, NewMessage { content: "second".to_string() });

        armin.mark_supabase_messages_failed(&[msg1.id.clone()], "err");

        let config = LeviConfig {
            batch_size: 10,
            backoff_base: Duration::from_secs(60),
            backoff_max: Duration::from_secs(300),
            ..LeviConfig::default()
        };

        let mut buffer = Vec::new();
        let mut buffer_ids = HashSet::new();
        fill_from_outbox(&armin, &config, &mut buffer, &mut buffer_ids);

        assert_eq!(buffer.len(), 1);
        assert_eq!(buffer[0].message_id, msg2.id.as_str());
    }

    #[test]
    fn get_session_secret_key_errors_without_secret() {
        let sink = RecordingSink::new();
        let armin = Arc::new(Armin::in_memory(sink).unwrap());
        let session_id = armin.create_session();

        let cache = Arc::new(Mutex::new(HashMap::new()));
        let db_key = Arc::new(Mutex::new(Some([7u8; 32])));

        let armin_handle: ArminHandle = armin.clone();
        let err = get_session_secret_key(&armin_handle, &cache, &db_key, session_id.as_str())
            .expect_err("expected missing session secret error");
        assert!(err.contains("missing session secret"));
    }
}
