//! Daemon state definition.

use crate::armin_adapter::DaemonArmin;
use crate::ably::AblyTokenBrokerCacheHandle;
use crate::itachi::idempotency::IdempotencyStore;
use crate::utils::SessionSecretCache;
use daemon_config_and_utils::{Config, Paths};
use daemon_database::AsyncDatabase;
use daemon_ipc::SubscriptionManager;
use daemon_storage::SecretsManager;
use gyomei::Gyomei;
use levi::Levi;
use levi::SessionSyncService;
use std::collections::HashMap;
use std::process::Child;
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, oneshot, RwLock};
use tokio::task::JoinHandle;
use toshinori::{AblyRealtimeSyncer, ToshinoriSink};
use ymir::{DaemonAuthRuntime, SupabaseClient};

/// Shared daemon state (thread-safe).
#[derive(Clone)]
pub struct DaemonState {
    #[allow(dead_code)]
    pub config: Arc<Config>,
    #[allow(dead_code)]
    pub paths: Arc<Paths>,
    /// Async database executor with dedicated SQLite thread.
    pub db: AsyncDatabase,
    pub secrets: Arc<Mutex<SecretsManager>>,
    /// Currently running Claude processes by session_id.
    pub claude_processes: Arc<Mutex<HashMap<String, broadcast::Sender<()>>>>,
    /// Currently running terminal processes by session_id.
    pub terminal_processes: Arc<Mutex<HashMap<String, broadcast::Sender<()>>>>,
    /// Cached database encryption key (derived from device private key).
    /// Updated after login when device private key is generated.
    pub db_encryption_key: Arc<Mutex<Option<[u8; 32]>>>,
    /// Subscription manager for streaming events to clients.
    pub subscriptions: SubscriptionManager,
    /// In-memory cache of decrypted session secrets.
    /// Checks memory first, then SQLite, then keychain (legacy).
    pub session_secret_cache: SessionSecretCache,
    /// Supabase REST client for device and secret distribution.
    pub supabase_client: Arc<SupabaseClient>,
    /// Unified auth runtime used by startup and IPC handlers.
    pub auth_runtime: Arc<DaemonAuthRuntime>,
    /// This device's ID (UUID). Updated after login.
    pub device_id: Arc<Mutex<Option<String>>>,
    /// This device's X25519 private key (for decrypting secrets). Updated after login.
    pub device_private_key: Arc<Mutex<Option<[u8; 32]>>>,
    /// Service for syncing sessions to Supabase.
    pub session_sync: Arc<SessionSyncService>,
    /// Toshinori sink for Supabase sync.
    pub toshinori: Arc<ToshinoriSink>,
    /// Levi worker for Supabase message sync.
    pub message_sync: Arc<Levi>,
    /// Optional Ably hot-path worker for conversation message publish.
    /// Stored behind an async lock so it can be installed lazily after login.
    pub realtime_message_sync: Arc<RwLock<Option<Arc<AblyRealtimeSyncer>>>>,
    /// Optional Falco child process managed by this daemon instance.
    pub falco_process: Arc<Mutex<Option<Child>>>,
    /// Optional Nagato child process managed by this daemon instance.
    pub nagato_process: Arc<Mutex<Option<Child>>>,
    /// Itachi in-memory idempotency store for UM remote commands.
    pub itachi_idempotency: Arc<Mutex<IdempotencyStore>>,
    /// Shutdown signal sender for Nagato socket listener.
    pub nagato_shutdown_tx: Arc<Mutex<Option<oneshot::Sender<()>>>>,
    /// Join handle for Nagato socket listener task.
    pub nagato_server_task: Arc<Mutex<Option<JoinHandle<()>>>>,
    /// Token used by Nagato sidecar when requesting Ably token details.
    pub ably_broker_nagato_token: String,
    /// Token used by Falco sidecar when requesting Ably token details.
    pub ably_broker_falco_token: String,
    /// Handle for clearing broker token cache on auth transitions (e.g. logout).
    pub ably_broker_cache: AblyTokenBrokerCacheHandle,
    /// Armin session engine for fast in-memory message reads.
    /// Provides snapshot, delta, and live subscription views.
    /// Uses UUID-based session IDs directly - no mapping needed.
    pub armin: Arc<DaemonArmin>,
    /// Rope-backed secure file reader/writer service.
    pub gyomei: Arc<Gyomei>,
}
