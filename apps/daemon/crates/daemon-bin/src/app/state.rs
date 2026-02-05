//! Daemon state definition.

use crate::armin_adapter::DaemonArmin;
use levi::SessionSyncService;
use crate::utils::SessionSecretCache;
use daemon_auth::SupabaseClient;
use daemon_core::{Config, Paths};
use daemon_database::DatabasePool;
use daemon_ipc::SubscriptionManager;
use daemon_storage::SecretsManager;
use levi::Levi;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use toshinori::ToshinoriSink;
use tokio::sync::broadcast;

/// Shared daemon state (thread-safe).
#[derive(Clone)]
pub struct DaemonState {
    #[allow(dead_code)]
    pub config: Arc<Config>,
    #[allow(dead_code)]
    pub paths: Arc<Paths>,
    /// Database connection pool (allows concurrent reads via WAL mode).
    pub db: Arc<DatabasePool>,
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
    /// Armin session engine for fast in-memory message reads.
    /// Provides snapshot, delta, and live subscription views.
    /// Uses UUID-based session IDs directly - no mapping needed.
    pub armin: Arc<DaemonArmin>,
}
