//! # MessageSyncWorker: Supabase Message Sync Worker
//!
//! MessageSyncWorker is the daemon's message synchronization engine responsible for reliably
//! syncing encrypted messages to Supabase with batching, retries, and exponential
//! backoff.
//!
//! ## Overview
//!
//! The crate provides two main services:
//!
//! - **[`MessageSyncWorker`]**: The core message sync worker that batches messages, encrypts
//!   them with session-specific keys, and syncs to Supabase with retry handling.
//!
//! - **[`SessionSyncService`]**: Handles syncing coding sessions, repositories,
//!   and distributing session secrets across user devices.
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────┐     ┌─────────────┐     ┌──────────────┐
//! │  Message Queue  │────▶│    MessageSyncWorker     │────▶│   Supabase   │
//! │  (MPSC Channel) │     │  (Batcher)  │     │   (Cloud)    │
//! └─────────────────┘     └──────┬──────┘     └──────────────┘
//!                                │
//!                         ┌──────▼──────┐
//!                         │   SQLite    │
//!                         │ Sync State  │
//!                         │  (Cursor)   │
//!                         └─────────────┘
//! ```
//!
//! ## Key Features
//!
//! - **Cursor-based sync**: Tracks last synced sequence number per session,
//!   eliminating the need for per-message outbox entries.
//!
//! - **Batching**: Collects messages until batch size (default 50) or flush
//!   interval (default 500ms) is reached for efficient network usage.
//!
//! - **Encryption**: Messages are encrypted using XChaCha20-Poly1305 with
//!   session-specific symmetric keys before transmission.
//!
//! - **Retry Queue**: Failed syncs are retried with exponential backoff
//!   (2s → 4s → 8s → ... → 300s max) per session.
//!
//! - **Secret Caching**: Decrypted session keys are cached in memory to avoid
//!   repeated decryption operations.
//!
//! ## Example
//!
//! ```ignore
//! use message_sync_retriable_worker::{MessageSyncWorker, MessageSyncWorkerConfig};
//!
//! let config = MessageSyncWorkerConfig::default();
//! let worker = MessageSyncWorker::new(config, api_url, anon_key, armin, db_key);
//! worker.start();
//!
//! // Set authentication context
//! worker.set_context(SyncContext { access_token }).await;
//!
//! // Messages are automatically batched and synced via cursor-based tracking
//! worker.enqueue(MessageSyncRequest { ... });
//! ```

mod session_sync;

pub use session_sync::{SessionSyncService, SyncError, SyncResult};

use agent_session_sqlite_persist_core::{SessionId, SessionPendingSync, SessionReader, SessionWriter};
use base64::Engine;
use chrono::{DateTime, Utc};
use daemon_config_and_utils::encrypt_conversation_message;
use daemon_storage::SecretsManager;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use tokio::sync::{mpsc, RwLock};
use tokio::time::{interval, Duration};
use session_sync_sink::{MessageSyncRequest, MessageSyncer, MessageUpsert, SupabaseClient, SyncContext};
use tracing::{debug, error, warn};

/// Base64 encoding engine for ciphertext and nonces.
const BASE64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

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
/// Used throughout MessageSyncWorker to read session secrets and mark message sync status.
pub type ArminHandle = Arc<dyn ArminAccess + Send + Sync>;

/// Configuration for MessageSyncWorker batching and retry behavior.
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
pub struct MessageSyncWorkerConfig {
    /// Maximum number of messages to include in a single batch.
    pub batch_size: usize,
    /// How long to wait before flushing an incomplete batch.
    pub flush_interval: Duration,
    /// Base duration for exponential backoff on retries.
    pub backoff_base: Duration,
    /// Maximum duration for backoff (caps exponential growth).
    pub backoff_max: Duration,
    /// Maximum number of retries before permanently abandoning a session's sync.
    /// Prevents MessageSyncWorker from endlessly retrying sessions with permanent failures
    /// (e.g., secrets encrypted with a stale device key).
    pub max_retries: i32,
}

impl Default for MessageSyncWorkerConfig {
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

/// MessageSyncWorker message sync worker.
///
/// The main message synchronization engine that:
/// - Receives messages via MPSC channel
/// - Batches messages for efficient network usage
/// - Uses cursor-based sync state to track progress per session
/// - Encrypts message content with session-specific symmetric keys
/// - Syncs batches to Supabase
/// - Tracks sync state in Armin
///
/// # Lifecycle
///
/// 1. Create with [`MessageSyncWorker::new()`]
/// 2. Call [`MessageSyncWorker::start()`] to spawn the background worker
/// 3. Set authentication context with [`MessageSyncWorker::set_context()`]
/// 4. Enqueue messages via [`MessageSyncer::enqueue()`] trait
///
/// # Thread Safety
///
/// MessageSyncWorker is designed for concurrent access:
/// - Message sender (`mpsc::Sender`) is cloneable
/// - Context is protected by `RwLock`
/// - Caches are protected by `Mutex`
pub struct MessageSyncWorker {
    /// Configuration for batching and retry behavior.
    config: MessageSyncWorkerConfig,
    /// Supabase HTTP client for API calls.
    client: SupabaseClient,
    /// Handle to local session storage (Armin).
    armin: ArminHandle,
    /// Authentication context containing access token.
    context: Arc<RwLock<Option<SyncContext>>>,
    /// Channel sender for enqueuing new messages (triggers sync check).
    sender: mpsc::Sender<MessageSyncRequest>,
    /// Channel receiver (taken by worker on start).
    receiver: Mutex<Option<mpsc::Receiver<MessageSyncRequest>>>,
    /// In-memory cache of decrypted session secret keys.
    secret_cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
    /// Database encryption key for decrypting session secrets.
    db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
}

impl MessageSyncWorker {
    /// Creates a new MessageSyncWorker message sync worker.
    ///
    /// # Arguments
    ///
    /// * `config` - Batching and retry configuration
    /// * `api_url` - Supabase API URL (e.g., `https://xxx.supabase.co`)
    /// * `anon_key` - Supabase anonymous API key
    /// * `agent-session-sqlite-persist-core` - Handle to local session storage
    /// * `db_encryption_key` - Key for decrypting stored session secrets
    ///
    /// # Returns
    ///
    /// A new `MessageSyncWorker` instance ready to be started with [`start()`](Self::start).
    pub fn new(
        config: MessageSyncWorkerConfig,
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
    /// 1. Receives message notifications from the channel
    /// 2. On flush interval or batch triggers, queries SQLite for pending messages
    /// 3. Respects exponential backoff per session
    /// 4. Encrypts and sends batch to Supabase
    /// 5. Updates sync state in Armin (cursor position or failure)
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
            .expect("MessageSyncWorker already started");

        let config = self.config.clone();
        let client = self.client.clone();
        let armin = self.armin.clone();
        let context = self.context.clone();
        let secret_cache = self.secret_cache.clone();
        let db_encryption_key = self.db_encryption_key.clone();

        tokio::spawn(async move {
            // Track sessions that have pending messages from channel notifications
            let mut pending_session_ids: HashSet<String> = HashSet::new();
            let mut ticker = interval(config.flush_interval);

            loop {
                let mut flush_now = false;

                tokio::select! {
                    maybe_msg = receiver.recv() => {
                        match maybe_msg {
                            Some(msg) => {
                                // Track that this session has pending messages
                                pending_session_ids.insert(msg.session_id.clone());
                                if pending_session_ids.len() >= config.batch_size {
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
                    pending_session_ids.clear();

                    // Query SQLite for all sessions with pending messages
                    let sessions_to_sync = match armin.get_sessions_pending_sync(config.batch_size)
                    {
                        Ok(sessions) => sessions,
                        Err(e) => {
                            warn!(error = %e, "MessageSyncWorker failed to query pending sessions");
                            continue;
                        }
                    };
                    let now = Utc::now();

                    for session_pending in sessions_to_sync {
                        // Permanently skip sessions that have exceeded max retries
                        if session_pending.retry_count > config.max_retries {
                            debug!(
                                session_id = %session_pending.session_id.as_str(),
                                retry_count = session_pending.retry_count,
                                max_retries = config.max_retries,
                                "Skipping session sync (max retries exceeded)"
                            );
                            continue;
                        }

                        // Check if this session is due for retry based on backoff
                        if !is_session_due(
                            session_pending.last_attempt_at,
                            session_pending.retry_count,
                            now,
                            &config,
                        ) {
                            continue;
                        }

                        let session_id_for_log = session_pending.session_id.as_str().to_string();
                        let retry_count = session_pending.retry_count;

                        if let Err(err) = send_session_batch(
                            &client,
                            &armin,
                            &context,
                            &secret_cache,
                            &db_encryption_key,
                            session_pending,
                        )
                        .await
                        {
                            warn!(
                                session_id = %session_id_for_log,
                                retry_count = retry_count,
                                error = %err,
                                "MessageSyncWorker session batch failed"
                            );
                        }
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

impl MessageSyncer for MessageSyncWorker {
    /// Enqueues a message for synchronization.
    ///
    /// This notifies MessageSyncWorker that messages are available to sync. The actual
    /// sync is cursor-based - MessageSyncWorker will query SQLite for all messages
    /// beyond the last synced sequence number.
    ///
    /// # Arguments
    ///
    /// * `request` - The message sync request (used as a notification trigger)
    fn enqueue(&self, request: MessageSyncRequest) {
        if let Err(err) = self.sender.try_send(request) {
            debug!(error = %err, "MessageSyncWorker enqueue failed");
        }
    }
}

/// Sends a batch of messages for a single session to Supabase.
///
/// For each message in the session's pending list:
/// 1. Encrypts content using the session's symmetric key
/// 2. Builds an upsert payload with encrypted content and nonce
///
/// Then sends the entire batch to Supabase in a single API call.
///
/// # Success Path
///
/// - Updates sync state cursor to the highest synced sequence number
/// - Resets retry count to 0
///
/// # Failure Path
///
/// - Increments retry count for the session
/// - Stores error message for debugging
///
/// # Arguments
///
/// * `client` - Supabase HTTP client
/// * `agent-session-sqlite-persist-core` - Handle to local session storage
/// * `context` - Authentication context with access token
/// * `secret_cache` - Cache of decrypted session keys
/// * `db_encryption_key` - Key for decrypting session secrets from storage
/// * `session_pending` - Session with pending messages to sync
///
/// # Returns
///
/// `Ok(())` on success, `Err(String)` with error message on API failure.
async fn send_session_batch(
    client: &SupabaseClient,
    armin: &ArminHandle,
    context: &Arc<RwLock<Option<SyncContext>>>,
    secret_cache: &Arc<Mutex<HashMap<String, Vec<u8>>>>,
    db_encryption_key: &Arc<Mutex<Option<[u8; 32]>>>,
    session_pending: SessionPendingSync,
) -> Result<(), String> {
    let ctx = {
        let guard = context.read().await;
        guard.clone()
    };
    let Some(ctx) = ctx else {
        debug!("MessageSyncWorker: skipping batch (no context)");
        return Ok(());
    };

    if session_pending.messages.is_empty() {
        return Ok(());
    }

    let session_id = &session_pending.session_id;
    let mut payloads: Vec<MessageUpsert> = Vec::new();
    let mut max_sequence: i64 = session_pending.last_synced_sequence_number;

    for message in &session_pending.messages {
        match encrypt_message(
            armin,
            secret_cache,
            db_encryption_key,
            session_id.as_str(),
            message.content.as_bytes(),
        ) {
            Ok((cipher_b64, nonce_b64)) => {
                payloads.push(MessageUpsert {
                    session_id: session_id.as_str().to_string(),
                    sequence_number: message.sequence_number,
                    content_encrypted: Some(cipher_b64),
                    content_nonce: Some(nonce_b64),
                });
                max_sequence = max_sequence.max(message.sequence_number);
            }
            Err(err) => {
                // If encryption fails for any message, fail the whole session batch
                let _ = armin.mark_supabase_sync_failed(session_id, &err);
                return Err(err);
            }
        }
    }

    if payloads.is_empty() {
        return Ok(());
    }

    match client
        .upsert_messages_batch(&payloads, &ctx.access_token)
        .await
    {
        Ok(()) => {
            let _ = armin.mark_supabase_sync_success(session_id, max_sequence);
            Ok(())
        }
        Err(err) => {
            let error = err.to_string();
            let _ = armin.mark_supabase_sync_failed(session_id, &error);
            Err(error)
        }
    }
}

/// Encrypts a message using the session's symmetric key.
///
/// Uses ChaCha20-Poly1305 authenticated encryption with:
/// - A random 12-byte nonce (generated fresh for each message)
/// - The session's 32-byte symmetric key
///
/// # Arguments
///
/// * `agent-session-sqlite-persist-core` - Handle to local session storage (for retrieving session secret)
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
    let encrypted = encrypt_conversation_message(&key, plaintext).map_err(|e| e.to_string())?;
    Ok((encrypted.content_encrypted_b64, encrypted.content_nonce_b64))
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
/// * `agent-session-sqlite-persist-core` - Handle to local session storage
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
        .map_err(|e| format!("failed to get session secret: {}", e))?
        .ok_or_else(|| "missing session secret".to_string())?;

    debug!(
        session_id = %session_id,
        db_key_len = db_key.len(),
        nonce_len = session_secret.nonce.len(),
        encrypted_len = session_secret.encrypted_secret.len(),
        nonce_b64 = %BASE64.encode(&session_secret.nonce),
        "Decrypting session secret"
    );

    let plaintext = daemon_database::decrypt_content(
        &db_key,
        &session_secret.nonce,
        &session_secret.encrypted_secret,
    )
    .map_err(|e| {
            error!(
                session_id = %session_id,
                nonce_len = session_secret.nonce.len(),
                encrypted_len = session_secret.encrypted_secret.len(),
                "Session secret decryption failed: {}", e
            );
            format!(
                "failed to decrypt session secret for session {}: {} (this usually indicates a stale database encryption key or corrupted session secret record)",
                session_id, e
            )
        })?;

    let secret_str = String::from_utf8(plaintext).map_err(|e| e.to_string())?;
    let key = SecretsManager::parse_session_secret(&secret_str).map_err(|e| {
        format!(
            "invalid session secret format for session {}: {}",
            session_id, e
        )
    })?;

    // Cache for future use
    secret_cache
        .lock()
        .expect("lock poisoned")
        .insert(session_id.to_string(), key.clone());

    Ok(key)
}

/// Determines if a session is due for sync based on exponential backoff.
///
/// A session is due if:
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
/// `true` if the session should be included in the next sync batch.
fn is_session_due(
    last_attempt_at: Option<DateTime<Utc>>,
    retry_count: i32,
    now: DateTime<Utc>,
    config: &MessageSyncWorkerConfig,
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
fn compute_backoff(retry_count: i32, config: &MessageSyncWorkerConfig) -> chrono::Duration {
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
    use agent_session_sqlite_persist_core::{Armin, NewMessage, NewSessionSecret, PendingSyncMessage, RecordingSink};
    use daemon_database::{encrypt_content, generate_nonce};

    fn setup_armin_with_secret() -> (ArminHandle, SessionId, Arc<Mutex<Option<[u8; 32]>>>) {
        let sink = RecordingSink::new();
        let armin = Arc::new(Armin::in_memory(sink).unwrap());
        let session_id = armin.create_session().unwrap();

        let session_secret = SecretsManager::generate_session_secret();
        let db_key = [42u8; 32];
        let nonce = generate_nonce();
        let encrypted = encrypt_content(&db_key, &nonce, session_secret.as_bytes()).unwrap();

        armin
            .set_session_secret(NewSessionSecret {
                session_id: session_id.clone(),
                encrypted_secret: encrypted,
                nonce: nonce.to_vec(),
            })
            .unwrap();

        (
            armin as ArminHandle,
            session_id,
            Arc::new(Mutex::new(Some(db_key))),
        )
    }

    #[test]
    fn compute_backoff_caps_and_grows() {
        let config = MessageSyncWorkerConfig {
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(10),
            ..MessageSyncWorkerConfig::default()
        };

        assert_eq!(compute_backoff(0, &config), chrono::Duration::zero());
        assert_eq!(compute_backoff(1, &config), chrono::Duration::seconds(2));
        assert_eq!(compute_backoff(2, &config), chrono::Duration::seconds(4));
        assert_eq!(compute_backoff(3, &config), chrono::Duration::seconds(8));
        assert_eq!(compute_backoff(4, &config), chrono::Duration::seconds(10));
        assert_eq!(compute_backoff(10, &config), chrono::Duration::seconds(10));
    }

    #[test]
    fn is_session_due_respects_backoff() {
        let config = MessageSyncWorkerConfig {
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(10),
            ..MessageSyncWorkerConfig::default()
        };

        let now = Utc::now();
        assert!(is_session_due(None, 0, now, &config));

        let last_attempt = now;
        assert!(!is_session_due(Some(last_attempt), 1, now, &config));
        assert!(is_session_due(
            Some(last_attempt),
            1,
            now + chrono::Duration::seconds(3),
            &config
        ));
    }

    #[test]
    fn encrypt_message_caches_secret() {
        let (armin, session_id, db_key) = setup_armin_with_secret();
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let result = encrypt_message(&armin, &cache, &db_key, session_id.as_str(), b"hello");
        assert!(result.is_ok());

        let cached = cache.lock().unwrap();
        assert!(cached.contains_key(session_id.as_str()));
    }

    #[test]
    fn get_session_secret_key_errors_without_secret() {
        let sink = RecordingSink::new();
        let armin = Arc::new(Armin::in_memory(sink).unwrap());
        let session_id = armin.create_session().unwrap();

        let cache = Arc::new(Mutex::new(HashMap::new()));
        let db_key = Arc::new(Mutex::new(Some([7u8; 32])));

        let armin_handle: ArminHandle = armin.clone();
        let err = get_session_secret_key(&armin_handle, &cache, &db_key, session_id.as_str())
            .expect_err("expected missing session secret error");
        assert!(err.contains("missing session secret"));
    }

    #[test]
    fn compute_backoff_zero_for_non_positive_retries() {
        let config = MessageSyncWorkerConfig::default();
        assert_eq!(compute_backoff(0, &config), chrono::Duration::zero());
        assert_eq!(compute_backoff(-1, &config), chrono::Duration::zero());
        assert_eq!(compute_backoff(-100, &config), chrono::Duration::zero());
    }

    #[test]
    fn compute_backoff_large_retry_count_saturates() {
        let config = MessageSyncWorkerConfig {
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(300),
            ..MessageSyncWorkerConfig::default()
        };

        // Very large retry count should cap at max, not overflow
        assert_eq!(
            compute_backoff(100, &config),
            chrono::Duration::seconds(300)
        );
        assert_eq!(
            compute_backoff(i32::MAX, &config),
            chrono::Duration::seconds(300)
        );
    }

    #[test]
    fn is_session_due_zero_retry_always_due() {
        let config = MessageSyncWorkerConfig::default();
        let now = Utc::now();

        // With retry_count 0, backoff is zero — so it's always due even if last attempt was now
        assert!(is_session_due(Some(now), 0, now, &config));
    }

    #[test]
    fn is_session_due_exactly_at_boundary() {
        let config = MessageSyncWorkerConfig {
            backoff_base: Duration::from_secs(2),
            backoff_max: Duration::from_secs(300),
            ..MessageSyncWorkerConfig::default()
        };

        let now = Utc::now();
        let last_attempt = now;
        // retry_count=1 → backoff=2s, checking exactly at +2s should be due
        assert!(is_session_due(
            Some(last_attempt),
            1,
            now + chrono::Duration::seconds(2),
            &config,
        ));
        // 1ms before should not be due
        assert!(!is_session_due(
            Some(last_attempt),
            1,
            now + chrono::Duration::milliseconds(1999),
            &config,
        ));
    }

    #[test]
    fn get_session_secret_key_returns_from_cache() {
        let (armin, session_id, db_key) = setup_armin_with_secret();
        let cache = Arc::new(Mutex::new(HashMap::new()));

        // First call populates cache
        let key1 = get_session_secret_key(&armin, &cache, &db_key, session_id.as_str()).unwrap();

        // Wipe the db_key so a non-cached path would fail
        *db_key.lock().unwrap() = None;

        // Second call should still succeed from cache
        let key2 = get_session_secret_key(&armin, &cache, &db_key, session_id.as_str()).unwrap();
        assert_eq!(key1, key2);
    }

    #[test]
    fn get_session_secret_key_errors_without_db_key() {
        let (armin, session_id, _) = setup_armin_with_secret();
        let cache = Arc::new(Mutex::new(HashMap::new()));
        let no_db_key = Arc::new(Mutex::new(None));

        let err = get_session_secret_key(&armin, &cache, &no_db_key, session_id.as_str())
            .expect_err("expected missing db key error");
        assert!(err.contains("missing database encryption key"));
    }

    #[test]
    fn encrypt_message_errors_without_db_key() {
        let (armin, session_id, _) = setup_armin_with_secret();
        let cache = Arc::new(Mutex::new(HashMap::new()));
        let no_db_key = Arc::new(Mutex::new(None));

        let err = encrypt_message(&armin, &cache, &no_db_key, session_id.as_str(), b"hello")
            .expect_err("expected error without db key");
        assert!(err.contains("missing database encryption key"));
    }

    #[test]
    fn encrypt_message_produces_different_ciphertext_each_time() {
        let (armin, session_id, db_key) = setup_armin_with_secret();
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let (cipher1, nonce1) =
            encrypt_message(&armin, &cache, &db_key, session_id.as_str(), b"hello").unwrap();
        let (cipher2, nonce2) =
            encrypt_message(&armin, &cache, &db_key, session_id.as_str(), b"hello").unwrap();

        // Different nonces → different ciphertext (nonces are random)
        assert_ne!(nonce1, nonce2);
        assert_ne!(cipher1, cipher2);
    }

    #[test]
    fn encrypt_message_output_is_valid_base64() {
        let (armin, session_id, db_key) = setup_armin_with_secret();
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let (cipher_b64, nonce_b64) =
            encrypt_message(&armin, &cache, &db_key, session_id.as_str(), b"test data").unwrap();

        // Both should decode as valid base64
        assert!(BASE64.decode(&cipher_b64).is_ok());
        assert!(BASE64.decode(&nonce_b64).is_ok());

        // Nonce should be 12 bytes (NONCE_SIZE)
        let nonce_bytes = BASE64.decode(&nonce_b64).unwrap();
        assert_eq!(nonce_bytes.len(), 12);
    }

    #[test]
    fn cursor_based_sync_state() {
        let sink = RecordingSink::new();
        let armin = Arc::new(Armin::in_memory(sink).unwrap());
        let session_id = armin.create_session().unwrap();

        // Initially no sync state
        let state = armin.get_supabase_sync_state(&session_id).unwrap();
        assert!(state.is_none());

        // Append some messages
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "msg1".to_string(),
                },
            )
            .unwrap();
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "msg2".to_string(),
                },
            )
            .unwrap();
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "msg3".to_string(),
                },
            )
            .unwrap();

        // Check pending sync
        let pending = armin.get_sessions_pending_sync(100).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].messages.len(), 3);
        assert_eq!(pending[0].last_synced_sequence_number, 0);

        // Mark sync success up to sequence 2
        armin.mark_supabase_sync_success(&session_id, 2).unwrap();

        // Check state updated
        let state = armin.get_supabase_sync_state(&session_id).unwrap().unwrap();
        assert_eq!(state.last_synced_sequence_number, 2);
        assert_eq!(state.retry_count, 0);

        // Only message 3 should be pending now
        let pending = armin.get_sessions_pending_sync(100).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].messages.len(), 1);
        assert_eq!(pending[0].messages[0].sequence_number, 3);

        // Mark sync failed
        armin
            .mark_supabase_sync_failed(&session_id, "test error")
            .unwrap();

        let state = armin.get_supabase_sync_state(&session_id).unwrap().unwrap();
        assert_eq!(state.retry_count, 1);
        assert_eq!(state.last_error.as_deref(), Some("test error"));
    }

    // ========================================================================
    // send_session_batch tests
    // ========================================================================

    fn make_test_client() -> SupabaseClient {
        SupabaseClient::new("http://localhost:54321", "test-anon-key")
    }

    fn make_pending_sync(session_id: &SessionId, messages: Vec<(&str, i64)>) -> SessionPendingSync {
        SessionPendingSync {
            session_id: session_id.clone(),
            last_synced_sequence_number: 0,
            retry_count: 0,
            last_attempt_at: None,
            messages: messages
                .into_iter()
                .map(|(content, seq)| PendingSyncMessage {
                    session_id: session_id.clone(),
                    message_id: agent_session_sqlite_persist_core::MessageId::from_string(format!("msg-{}", seq)),
                    sequence_number: seq,
                    content: content.to_string(),
                })
                .collect(),
        }
    }

    #[tokio::test]
    async fn send_session_batch_skips_when_no_context() {
        let (armin, session_id, db_key) = setup_armin_with_secret();
        let client = make_test_client();
        let context = Arc::new(RwLock::new(None)); // No context set
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let pending = make_pending_sync(&session_id, vec![("hello", 1)]);

        let result = send_session_batch(&client, &armin, &context, &cache, &db_key, pending).await;
        assert!(result.is_ok());

        // No sync state should be written (batch was skipped)
        let state = armin.get_supabase_sync_state(&session_id).unwrap();
        assert!(state.is_none());
    }

    #[tokio::test]
    async fn send_session_batch_skips_empty_messages() {
        let (armin, session_id, db_key) = setup_armin_with_secret();
        let client = make_test_client();
        let context = Arc::new(RwLock::new(Some(SyncContext {
            access_token: "test-token".to_string(),
            user_id: "test-user".to_string(),
            device_id: "test-device".to_string(),
        })));
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let pending = make_pending_sync(&session_id, vec![]);

        let result = send_session_batch(&client, &armin, &context, &cache, &db_key, pending).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn send_session_batch_fails_encryption_without_db_key() {
        let (armin, session_id, _) = setup_armin_with_secret();
        let client = make_test_client();
        let context = Arc::new(RwLock::new(Some(SyncContext {
            access_token: "test-token".to_string(),
            user_id: "test-user".to_string(),
            device_id: "test-device".to_string(),
        })));
        let cache = Arc::new(Mutex::new(HashMap::new()));
        let no_db_key = Arc::new(Mutex::new(None));

        let pending = make_pending_sync(&session_id, vec![("hello", 1)]);

        let result =
            send_session_batch(&client, &armin, &context, &cache, &no_db_key, pending).await;
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .contains("missing database encryption key"));

        // Should have marked sync as failed
        let state = armin.get_supabase_sync_state(&session_id).unwrap().unwrap();
        assert_eq!(state.retry_count, 1);
        assert!(state
            .last_error
            .as_deref()
            .unwrap()
            .contains("missing database encryption key"));
    }

    #[tokio::test]
    async fn send_session_batch_encrypts_and_tracks_max_sequence() {
        // This test verifies encryption succeeds for all messages but the API call
        // will fail (no real server). We verify the error path marks failure.
        let (armin, session_id, db_key) = setup_armin_with_secret();
        let client = make_test_client();
        let context = Arc::new(RwLock::new(Some(SyncContext {
            access_token: "test-token".to_string(),
            user_id: "test-user".to_string(),
            device_id: "test-device".to_string(),
        })));
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let pending = make_pending_sync(&session_id, vec![("msg1", 1), ("msg2", 2), ("msg3", 3)]);

        // Will fail at the API call since there's no real server
        let result = send_session_batch(&client, &armin, &context, &cache, &db_key, pending).await;
        assert!(result.is_err());

        // Sync should be marked as failed (API error)
        let state = armin.get_supabase_sync_state(&session_id).unwrap().unwrap();
        assert_eq!(state.retry_count, 1);
        assert!(state.last_error.is_some());

        // But the secret should have been cached from the encryption step
        let cached = cache.lock().unwrap();
        assert!(cached.contains_key(session_id.as_str()));
    }

    // ========================================================================
    // MessageSyncWorker struct tests
    // ========================================================================

    #[tokio::test]
    async fn levi_set_and_clear_context() {
        let sink = RecordingSink::new();
        let armin: ArminHandle = Arc::new(Armin::in_memory(sink).unwrap());
        let db_key = Arc::new(Mutex::new(Some([0u8; 32])));

        let worker = MessageSyncWorker::new(
            MessageSyncWorkerConfig::default(),
            "http://localhost:54321",
            "test-key",
            armin,
            db_key,
        );

        // Initially no context
        {
            let guard = worker.context.read().await;
            assert!(guard.is_none());
        }

        // Set context
        worker.set_context(SyncContext {
            access_token: "token-123".to_string(),
            user_id: "user-1".to_string(),
            device_id: "device-1".to_string(),
        })
        .await;

        {
            let guard = worker.context.read().await;
            assert!(guard.is_some());
            assert_eq!(guard.as_ref().unwrap().access_token, "token-123");
        }

        // Clear context
        worker.clear_context().await;

        {
            let guard = worker.context.read().await;
            assert!(guard.is_none());
        }
    }

    #[test]
    fn levi_enqueue_sends_to_channel() {
        let sink = RecordingSink::new();
        let armin: ArminHandle = Arc::new(Armin::in_memory(sink).unwrap());
        let db_key = Arc::new(Mutex::new(Some([0u8; 32])));

        let worker = MessageSyncWorker::new(
            MessageSyncWorkerConfig::default(),
            "http://localhost:54321",
            "test-key",
            armin,
            db_key,
        );

        // Enqueue a message — should not panic
        worker.enqueue(MessageSyncRequest {
            session_id: "session-1".to_string(),
            message_id: "msg-1".to_string(),
            sequence_number: 1,
            content: "hello".to_string(),
        });

        // Verify it landed in the channel by taking the receiver and checking
        let mut receiver = worker.receiver.lock().unwrap().take().unwrap();
        let msg = receiver.try_recv().unwrap();
        assert_eq!(msg.session_id, "session-1");
        assert_eq!(msg.sequence_number, 1);
    }

    #[test]
    fn levi_new_starts_with_empty_cache() {
        let sink = RecordingSink::new();
        let armin: ArminHandle = Arc::new(Armin::in_memory(sink).unwrap());
        let db_key = Arc::new(Mutex::new(Some([0u8; 32])));

        let worker = MessageSyncWorker::new(
            MessageSyncWorkerConfig::default(),
            "http://localhost:54321",
            "test-key",
            armin,
            db_key,
        );

        assert!(worker.secret_cache.lock().unwrap().is_empty());
    }

    #[test]
    fn levi_config_default_values() {
        let config = MessageSyncWorkerConfig::default();
        assert_eq!(config.batch_size, 50);
        assert_eq!(config.flush_interval, Duration::from_millis(500));
        assert_eq!(config.backoff_base, Duration::from_secs(2));
        assert_eq!(config.backoff_max, Duration::from_secs(300));
        assert_eq!(config.max_retries, 20);
    }

    #[test]
    fn cursor_sync_multiple_success_advances_cursor() {
        let sink = RecordingSink::new();
        let armin = Arc::new(Armin::in_memory(sink).unwrap());
        let session_id = armin.create_session().unwrap();

        armin
            .append(
                &session_id,
                NewMessage {
                    content: "a".to_string(),
                },
            )
            .unwrap();
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "b".to_string(),
                },
            )
            .unwrap();
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "c".to_string(),
                },
            )
            .unwrap();
        armin
            .append(
                &session_id,
                NewMessage {
                    content: "d".to_string(),
                },
            )
            .unwrap();

        // Sync first two
        armin.mark_supabase_sync_success(&session_id, 2).unwrap();
        let pending = armin.get_sessions_pending_sync(100).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].messages.len(), 2);
        assert_eq!(pending[0].messages[0].sequence_number, 3);
        assert_eq!(pending[0].messages[1].sequence_number, 4);

        // Sync remaining
        armin.mark_supabase_sync_success(&session_id, 4).unwrap();
        let pending = armin.get_sessions_pending_sync(100).unwrap();
        assert!(pending.is_empty());

        let state = armin.get_supabase_sync_state(&session_id).unwrap().unwrap();
        assert_eq!(state.last_synced_sequence_number, 4);
        assert_eq!(state.retry_count, 0);
    }

    #[test]
    fn cursor_sync_failure_then_success_resets_retry() {
        let sink = RecordingSink::new();
        let armin = Arc::new(Armin::in_memory(sink).unwrap());
        let session_id = armin.create_session().unwrap();

        armin
            .append(
                &session_id,
                NewMessage {
                    content: "a".to_string(),
                },
            )
            .unwrap();

        // Fail twice
        armin
            .mark_supabase_sync_failed(&session_id, "err1")
            .unwrap();
        armin
            .mark_supabase_sync_failed(&session_id, "err2")
            .unwrap();

        let state = armin.get_supabase_sync_state(&session_id).unwrap().unwrap();
        assert_eq!(state.retry_count, 2);
        assert_eq!(state.last_error.as_deref(), Some("err2"));

        // Now succeed
        armin.mark_supabase_sync_success(&session_id, 1).unwrap();

        let state = armin.get_supabase_sync_state(&session_id).unwrap().unwrap();
        assert_eq!(state.retry_count, 0);
        assert!(state.last_error.is_none());
        assert_eq!(state.last_synced_sequence_number, 1);
    }
}
