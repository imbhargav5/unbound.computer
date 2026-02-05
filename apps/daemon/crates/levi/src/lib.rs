//! # Levi: Supabase Message Sync Worker
//!
//! Levi is the daemon's message synchronization engine responsible for reliably
//! syncing encrypted messages to Supabase with batching, retries, and exponential
//! backoff.
//!
//! ## Overview
//!
//! The crate provides two main services:
//!
//! - **[`Levi`]**: The core message sync worker that batches messages, encrypts
//!   them with session-specific keys, and syncs to Supabase with retry handling.
//!
//! - **[`SessionSyncService`]**: Handles syncing coding sessions, repositories,
//!   and distributing session secrets across user devices.
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────┐     ┌─────────────┐     ┌──────────────┐
//! │  Message Queue  │────▶│    Levi     │────▶│   Supabase   │
//! │  (MPSC Channel) │     │  (Batcher)  │     │   (Cloud)    │
//! └─────────────────┘     └──────┬──────┘     └──────────────┘
//!                                │
//!                         ┌──────▼──────┐
//!                         │   SQLite    │
//!                         │   Outbox    │
//!                         │  (Retries)  │
//!                         └─────────────┘
//! ```
//!
//! ## Key Features
//!
//! - **Batching**: Collects messages until batch size (default 50) or flush
//!   interval (default 500ms) is reached for efficient network usage.
//!
//! - **Encryption**: Messages are encrypted using XChaCha20-Poly1305 with
//!   session-specific symmetric keys before transmission.
//!
//! - **Retry Queue**: Failed messages are stored in a SQLite outbox and retried
//!   with exponential backoff (2s → 4s → 8s → ... → 300s max).
//!
//! - **Secret Caching**: Decrypted session keys are cached in memory to avoid
//!   repeated decryption operations.
//!
//! ## Example
//!
//! ```ignore
//! use levi::{Levi, LeviConfig};
//!
//! let config = LeviConfig::default();
//! let levi = Levi::new(config, api_url, anon_key, armin, db_key);
//! levi.start();
//!
//! // Set authentication context
//! levi.set_context(SyncContext { access_token }).await;
//!
//! // Messages are automatically batched and synced
//! levi.enqueue(MessageSyncRequest { ... });
//! ```

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

/// Base64 encoding engine for ciphertext and nonces.
const BASE64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

/// Default role assigned to synced messages.
const DEFAULT_ROLE: &str = "assistant";

/// Default capacity of the in-memory message queue.
const DEFAULT_QUEUE_CAPACITY: usize = 1024;

/// Combined trait for Armin session storage access.
///
/// This trait bounds types that can both read and write session data,
/// providing unified access to the local session storage.
pub trait ArminAccess: SessionWriter + SessionReader {}

impl<T: SessionWriter + SessionReader> ArminAccess for T {}

/// Thread-safe handle for accessing Armin session storage.
///
/// Used throughout Levi to read session secrets and mark message sync status.
pub type ArminHandle = Arc<dyn ArminAccess + Send + Sync>;

/// Configuration for Levi batching and retry behavior.
///
/// Controls how messages are batched for network efficiency and how
/// failed messages are retried with exponential backoff.
///
/// # Fields
///
/// - `batch_size`: Maximum messages per batch (default: 50)
/// - `flush_interval`: Time to wait before flushing incomplete batches (default: 500ms)
/// - `backoff_base`: Initial retry delay for failed messages (default: 2s)
/// - `backoff_max`: Maximum retry delay cap (default: 300s / 5 minutes)
///
/// # Backoff Calculation
///
/// Retry delay follows exponential backoff: `base * 2^(retry_count - 1)`
/// capped at `backoff_max`. For default config:
/// - 1st retry: 2s
/// - 2nd retry: 4s
/// - 3rd retry: 8s
/// - 4th retry: 16s
/// - ... up to 300s max
#[derive(Debug, Clone)]
pub struct LeviConfig {
    /// Maximum number of messages to include in a single batch.
    pub batch_size: usize,
    /// How long to wait before flushing an incomplete batch.
    pub flush_interval: Duration,
    /// Base duration for exponential backoff on retries.
    pub backoff_base: Duration,
    /// Maximum duration for backoff (caps exponential growth).
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
///
/// The main message synchronization engine that:
/// - Receives messages via MPSC channel
/// - Batches messages for efficient network usage
/// - Fills batches from SQLite outbox (retry queue) respecting backoff
/// - Encrypts message content with session-specific symmetric keys
/// - Syncs batches to Supabase
/// - Tracks message sync status in Armin
///
/// # Lifecycle
///
/// 1. Create with [`Levi::new()`]
/// 2. Call [`Levi::start()`] to spawn the background worker
/// 3. Set authentication context with [`Levi::set_context()`]
/// 4. Enqueue messages via [`MessageSyncer::enqueue()`] trait
///
/// # Thread Safety
///
/// Levi is designed for concurrent access:
/// - Message sender (`mpsc::Sender`) is cloneable
/// - Context is protected by `RwLock`
/// - Caches are protected by `Mutex`
pub struct Levi {
    /// Configuration for batching and retry behavior.
    config: LeviConfig,
    /// Supabase HTTP client for API calls.
    client: SupabaseClient,
    /// Handle to local session storage (Armin).
    armin: ArminHandle,
    /// Authentication context containing access token.
    context: Arc<RwLock<Option<SyncContext>>>,
    /// Channel sender for enqueuing new messages.
    sender: mpsc::Sender<MessageSyncRequest>,
    /// Channel receiver (taken by worker on start).
    receiver: Mutex<Option<mpsc::Receiver<MessageSyncRequest>>>,
    /// In-memory cache of decrypted session secret keys.
    secret_cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
    /// Database encryption key for decrypting session secrets.
    db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
}

impl Levi {
    /// Creates a new Levi message sync worker.
    ///
    /// # Arguments
    ///
    /// * `config` - Batching and retry configuration
    /// * `api_url` - Supabase API URL (e.g., `https://xxx.supabase.co`)
    /// * `anon_key` - Supabase anonymous API key
    /// * `armin` - Handle to local session storage
    /// * `db_encryption_key` - Key for decrypting stored session secrets
    ///
    /// # Returns
    ///
    /// A new `Levi` instance ready to be started with [`start()`](Self::start).
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

    /// Starts the background worker loop.
    ///
    /// Spawns an async task that:
    /// 1. Receives messages from the channel
    /// 2. Buffers until batch_size or flush_interval is reached
    /// 3. Fills remaining capacity from SQLite outbox (respecting retry backoff)
    /// 4. Encrypts and sends batch to Supabase
    /// 5. Updates message status in Armin (sent/failed)
    ///
    /// # Panics
    ///
    /// Panics if called more than once (worker can only be started once).
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

    /// Sets the authentication context for Supabase API calls.
    ///
    /// Must be called after user authentication to enable message syncing.
    /// Without a context, batches will be skipped (logged at debug level).
    ///
    /// # Arguments
    ///
    /// * `context` - Contains the Supabase access token
    pub async fn set_context(&self, context: SyncContext) {
        let mut guard = self.context.write().await;
        *guard = Some(context);
    }

    /// Clears the authentication context.
    ///
    /// Call when user logs out to stop message syncing.
    pub async fn clear_context(&self) {
        let mut guard = self.context.write().await;
        *guard = None;
    }
}

impl MessageSyncer for Levi {
    /// Enqueues a message for synchronization.
    ///
    /// Messages are buffered in the in-memory channel and batched for
    /// efficient network transmission. If the channel is full, the message
    /// is dropped and a debug log is emitted.
    ///
    /// # Arguments
    ///
    /// * `request` - The message sync request containing message ID, session ID,
    ///               sequence number, and content
    fn enqueue(&self, request: MessageSyncRequest) {
        if let Err(err) = self.sender.try_send(request) {
            debug!(error = %err, "Levi enqueue failed");
        }
    }
}

/// Internal representation of a message queued for sync.
///
/// Unifies messages from two sources:
/// - New messages from the MPSC channel (via `from_request`)
/// - Retry messages from the SQLite outbox (via `from_pending`)
#[derive(Debug, Clone)]
struct QueuedMessage {
    /// Unique message identifier.
    message_id: String,
    /// Session this message belongs to.
    session_id: String,
    /// Message ordering within the session.
    sequence_number: i64,
    /// Plaintext message content (encrypted before sending).
    content: String,
}

impl QueuedMessage {
    /// Creates a queued message from a new sync request.
    fn from_request(req: MessageSyncRequest) -> Self {
        Self {
            message_id: req.message_id,
            session_id: req.session_id,
            sequence_number: req.sequence_number,
            content: req.content,
        }
    }

    /// Creates a queued message from a pending outbox entry.
    fn from_pending(pending: PendingSupabaseMessage) -> Self {
        Self {
            message_id: pending.message_id.as_str().to_string(),
            session_id: pending.session_id.as_str().to_string(),
            sequence_number: pending.sequence_number,
            content: pending.content,
        }
    }
}

/// Fills the message buffer from the SQLite outbox (retry queue).
///
/// Retrieves pending messages from Armin's outbox and adds them to the
/// buffer, respecting:
/// - Batch size limits
/// - Exponential backoff timing
/// - Deduplication (messages already in buffer are skipped)
///
/// # Arguments
///
/// * `armin` - Handle to local session storage
/// * `config` - Configuration with batch size and backoff settings
/// * `buffer` - Message buffer to fill
/// * `buffer_ids` - Set of message IDs already in buffer (for deduplication)
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

/// Sends a batch of messages to Supabase.
///
/// For each message in the batch:
/// 1. Encrypts content using the session's symmetric key
/// 2. Builds an upsert payload with encrypted content and nonce
///
/// Then sends the entire batch to Supabase in a single API call.
///
/// # Success Path
///
/// - Marks messages as sent in Armin
/// - Deletes messages from the outbox (they're synced, no retry needed)
///
/// # Failure Paths
///
/// - **Encryption failure**: Message is marked failed individually (won't block others)
/// - **API failure**: All messages in batch are marked failed (will be retried via outbox)
///
/// # Arguments
///
/// * `client` - Supabase HTTP client
/// * `armin` - Handle to local session storage
/// * `context` - Authentication context with access token
/// * `secret_cache` - Cache of decrypted session keys
/// * `db_encryption_key` - Key for decrypting session secrets from storage
/// * `batch` - Messages to send
///
/// # Returns
///
/// `Ok(())` on success, `Err(String)` with error message on API failure.
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

/// Encrypts a message using the session's symmetric key.
///
/// Uses XChaCha20-Poly1305 authenticated encryption with:
/// - A random 24-byte nonce (generated fresh for each message)
/// - The session's 32-byte symmetric key
///
/// # Arguments
///
/// * `armin` - Handle to local session storage (for retrieving session secret)
/// * `secret_cache` - Cache of decrypted session keys (avoids repeated decryption)
/// * `db_encryption_key` - Key for decrypting session secrets from storage
/// * `session_id` - ID of the session this message belongs to
/// * `plaintext` - Message content to encrypt
///
/// # Returns
///
/// A tuple of `(ciphertext_base64, nonce_base64)` for transmission to Supabase.
///
/// # Errors
///
/// Returns an error string if:
/// - Database encryption key is not set
/// - Session secret is not found
/// - Decryption of session secret fails
/// - Encryption fails
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

/// Retrieves the symmetric encryption key for a session.
///
/// Implements a caching strategy to avoid repeated decryption:
/// 1. Check in-memory cache first (fast path)
/// 2. If not cached, retrieve encrypted secret from Armin
/// 3. Decrypt the session secret using the database encryption key
/// 4. Parse the decrypted secret to extract the symmetric key
/// 5. Cache the key for future use
///
/// # Session Secret Format
///
/// Session secrets are stored encrypted in Armin using the database
/// encryption key. The decrypted secret is then parsed by `SecretsManager`
/// to extract the actual 32-byte symmetric key used for message encryption.
///
/// # Arguments
///
/// * `armin` - Handle to local session storage
/// * `secret_cache` - In-memory cache of decrypted keys
/// * `db_encryption_key` - Key for decrypting stored session secrets
/// * `session_id` - ID of the session to get the key for
///
/// # Returns
///
/// The 32-byte symmetric key as a `Vec<u8>`.
///
/// # Errors
///
/// Returns an error string if:
/// - Database encryption key is not available
/// - Session secret is not found in Armin
/// - Decryption fails
/// - Secret parsing fails
fn get_session_secret_key(
    armin: &ArminHandle,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    session_id: &str,
) -> Result<Vec<u8>, String> {
    // Fast path: check cache first
    if let Some(existing) = secret_cache
        .lock()
        .expect("lock poisoned")
        .get(session_id)
        .cloned()
    {
        return Ok(existing);
    }

    // Slow path: decrypt from storage
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

    // Cache for future use
    secret_cache
        .lock()
        .expect("lock poisoned")
        .insert(session_id.to_string(), key.clone());

    Ok(key)
}

/// Determines if a message is due for retry based on exponential backoff.
///
/// A message is due if:
/// - It has never been attempted (first sync attempt), OR
/// - Enough time has passed since the last attempt based on retry count
///
/// # Arguments
///
/// * `last_attempt_at` - When the last sync attempt occurred (None if never tried)
/// * `retry_count` - Number of previous failed attempts
/// * `now` - Current timestamp
/// * `config` - Configuration with backoff settings
///
/// # Returns
///
/// `true` if the message should be included in the next batch.
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

/// Computes the exponential backoff duration for a given retry count.
///
/// Implements binary exponential backoff:
/// - `delay = base * 2^(retry_count - 1)`, capped at `max`
///
/// # Examples (with default config: base=2s, max=300s)
///
/// | Retry Count | Delay |
/// |-------------|-------|
/// | 0           | 0s    |
/// | 1           | 2s    |
/// | 2           | 4s    |
/// | 3           | 8s    |
/// | 4           | 16s   |
/// | 5           | 32s   |
/// | 6           | 64s   |
/// | 7           | 128s  |
/// | 8+          | 300s (capped) |
///
/// # Arguments
///
/// * `retry_count` - Number of previous failed attempts
/// * `config` - Configuration with backoff base and max settings
///
/// # Returns
///
/// Duration to wait before the next retry attempt.
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
