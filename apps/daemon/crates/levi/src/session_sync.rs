//! Session synchronization service for syncing local sessions to Supabase.
//!
//! This service handles:
//! - Syncing repositories to Supabase (dependency for sessions)
//! - Syncing coding sessions to Supabase
//! - Distributing session secrets to all user devices

use base64::Engine;
use daemon_auth::{CodingSessionSecretRecord, SupabaseClient};
use daemon_database::{queries, DatabasePool};
use daemon_storage::SecretsManager;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tracing::{debug, info, warn};

const BASE64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

/// Result type for sync operations.
pub type SyncResult<T> = Result<T, SyncError>;

/// Errors that can occur during sync operations.
#[derive(Debug)]
pub enum SyncError {
    /// No authenticated session available.
    NotAuthenticated,
    /// No device identity configured.
    NoDeviceIdentity,
    /// Repository not found locally.
    RepositoryNotFound(String),
    /// Supabase API error.
    Supabase(String),
    /// Encryption error.
    Encryption(String),
}

impl std::fmt::Display for SyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncError::NotAuthenticated => write!(f, "Not authenticated"),
            SyncError::NoDeviceIdentity => write!(f, "No device identity configured"),
            SyncError::RepositoryNotFound(id) => write!(f, "Repository not found: {}", id),
            SyncError::Supabase(msg) => write!(f, "Supabase error: {}", msg),
            SyncError::Encryption(msg) => write!(f, "Encryption error: {}", msg),
        }
    }
}

impl std::error::Error for SyncError {}

/// Service for syncing sessions and secrets to Supabase.
pub struct SessionSyncService {
    supabase_client: Arc<SupabaseClient>,
    db: Arc<DatabasePool>,
    secrets: Arc<Mutex<SecretsManager>>,
    device_id: Arc<Mutex<Option<String>>>,
    device_private_key: Arc<Mutex<Option<[u8; 32]>>>,
    /// In-memory cache of session secrets for distribution.
    #[allow(dead_code)]
    session_secrets_cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

impl SessionSyncService {
    /// Create a new session sync service.
    pub fn new(
        supabase_client: Arc<SupabaseClient>,
        db: Arc<DatabasePool>,
        secrets: Arc<Mutex<SecretsManager>>,
        device_id: Arc<Mutex<Option<String>>>,
        device_private_key: Arc<Mutex<Option<[u8; 32]>>>,
        session_secrets_cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
    ) -> Self {
        Self {
            supabase_client,
            db,
            secrets,
            device_id,
            device_private_key,
            session_secrets_cache,
        }
    }

    /// Get authentication context (user_id, device_id, access_token).
    fn get_auth_context(&self) -> SyncResult<(String, String, String)> {
        let secrets = self.secrets.lock().unwrap();

        let meta = secrets
            .get_supabase_session_meta()
            .map_err(|e| SyncError::Supabase(e.to_string()))?
            .ok_or(SyncError::NotAuthenticated)?;

        let access_token = secrets
            .get_supabase_access_token()
            .map_err(|e| SyncError::Supabase(e.to_string()))?
            .ok_or(SyncError::NotAuthenticated)?;

        let device_id = self
            .device_id
            .lock()
            .unwrap()
            .clone()
            .ok_or(SyncError::NoDeviceIdentity)?;

        Ok((meta.user_id, device_id, access_token))
    }

    /// Sync a repository to Supabase.
    ///
    /// This must be called before syncing a session that references this repository.
    pub async fn sync_repository(&self, repository_id: &str) -> SyncResult<()> {
        let (user_id, device_id, access_token) = self.get_auth_context()?;

        // Get repository from local database
        let repo = {
            let conn = self
                .db
                .get()
                .map_err(|e| SyncError::Supabase(e.to_string()))?;
            queries::get_repository(&conn, repository_id)
                .map_err(|e| SyncError::Supabase(e.to_string()))?
                .ok_or_else(|| SyncError::RepositoryNotFound(repository_id.to_string()))?
        };

        self.supabase_client
            .upsert_repository(
                &repo.id,
                &user_id,
                &device_id,
                &repo.name,
                &repo.path,
                None,   // remote_url - TODO: add to local DB
                None,   // default_branch - TODO: add to local DB
                false,  // is_worktree
                None,   // worktree_branch
                &access_token,
            )
            .await
            .map_err(|e| SyncError::Supabase(e.to_string()))?;

        debug!(repository_id = %repository_id, "Repository synced to Supabase");
        Ok(())
    }

    /// Sync a coding session to Supabase.
    ///
    /// The repository must already be synced (call `sync_repository` first).
    pub async fn sync_session(
        &self,
        session_id: &str,
        repository_id: &str,
        status: &str,
    ) -> SyncResult<()> {
        let (user_id, device_id, access_token) = self.get_auth_context()?;

        self.supabase_client
            .upsert_coding_session(
                session_id,
                &user_id,
                &device_id,
                repository_id,
                status,
                None,   // current_branch
                None,   // working_directory
                false,  // is_worktree
                None,   // worktree_path
                &access_token,
            )
            .await
            .map_err(|e| SyncError::Supabase(e.to_string()))?;

        info!(session_id = %session_id, "Session synced to Supabase");
        Ok(())
    }

    /// Distribute a session secret to all user devices.
    ///
    /// Encrypts the secret for each device using hybrid encryption and stores
    /// in Supabase for cross-device access.
    ///
    /// Returns the number of devices the secret was distributed to.
    pub async fn distribute_secret(
        &self,
        session_id: &str,
        session_secret: &str,
    ) -> SyncResult<usize> {
        let (user_id, device_id, access_token) = self.get_auth_context()?;

        let device_private_key = self
            .device_private_key
            .lock()
            .unwrap()
            .ok_or(SyncError::NoDeviceIdentity)?;

        // Encrypt for this device first
        let this_device_public_key =
            daemon_core::hybrid_crypto::public_key_from_private(&device_private_key);

        let (ephemeral_pub, encrypted) = daemon_core::encrypt_for_device(
            session_secret.as_bytes(),
            &this_device_public_key,
            session_id,
        )
        .map_err(|e| SyncError::Encryption(e.to_string()))?;

        let mut records = vec![CodingSessionSecretRecord {
            session_id: session_id.to_string(),
            device_id: device_id.clone(),
            ephemeral_public_key: BASE64.encode(ephemeral_pub),
            encrypted_secret: BASE64.encode(encrypted),
        }];

        // Fetch other devices and encrypt for each
        let other_devices = self
            .supabase_client
            .fetch_user_devices(&user_id, &device_id, &access_token)
            .await
            .map_err(|e| SyncError::Supabase(e.to_string()))?;

        for device in &other_devices {
            let public_key_b64 = match &device.public_key {
                Some(k) => k,
                None => continue,
            };

            let public_key: [u8; 32] = match BASE64.decode(public_key_b64) {
                Ok(bytes) if bytes.len() == 32 => bytes.try_into().unwrap(),
                _ => {
                    warn!(device_id = %device.id, "Invalid public key, skipping");
                    continue;
                }
            };

            let (ephemeral_pub, encrypted) = match daemon_core::encrypt_for_device(
                session_secret.as_bytes(),
                &public_key,
                session_id,
            ) {
                Ok(result) => result,
                Err(e) => {
                    warn!(device_id = %device.id, "Failed to encrypt: {}", e);
                    continue;
                }
            };

            records.push(CodingSessionSecretRecord {
                session_id: session_id.to_string(),
                device_id: device.id.clone(),
                ephemeral_public_key: BASE64.encode(ephemeral_pub),
                encrypted_secret: BASE64.encode(encrypted),
            });
        }

        let count = records.len();

        self.supabase_client
            .insert_session_secrets(records, &access_token)
            .await
            .map_err(|e| SyncError::Supabase(e.to_string()))?;

        info!(
            session_id = %session_id,
            device_count = count,
            "Distributed session secret to devices"
        );

        Ok(count)
    }

    /// Sync a new session: repository, session, and secrets all at once.
    ///
    /// This is the main entry point for syncing a newly created session.
    pub async fn sync_new_session(
        &self,
        session_id: &str,
        repository_id: &str,
        session_secret: &str,
    ) -> SyncResult<()> {
        // Sync repository first (foreign key dependency)
        if let Err(e) = self.sync_repository(repository_id).await {
            warn!(
                session_id = %session_id,
                repository_id = %repository_id,
                "Failed to sync repository: {}",
                e
            );
            // Continue anyway - session sync might work if repo already exists
        }

        // Sync session
        if let Err(e) = self.sync_session(session_id, repository_id, "active").await {
            warn!(session_id = %session_id, "Failed to sync session: {}", e);
            // Continue to distribute secrets anyway
        }

        // Distribute secrets
        match self.distribute_secret(session_id, session_secret).await {
            Ok(count) => {
                debug!(
                    session_id = %session_id,
                    device_count = count,
                    "Session sync complete"
                );
            }
            Err(e) => {
                warn!(
                    session_id = %session_id,
                    "Failed to distribute secrets: {}",
                    e
                );
            }
        }

        Ok(())
    }

    /// Cache a session secret in memory (for local fast access).
    #[allow(dead_code)]
    pub fn cache_secret(&self, session_id: &str, secret_key: Vec<u8>) {
        let mut cache = self.session_secrets_cache.lock().unwrap();
        cache.insert(session_id.to_string(), secret_key);
    }

    /// Get a cached session secret.
    #[allow(dead_code)]
    pub fn get_cached_secret(&self, session_id: &str) -> Option<Vec<u8>> {
        let cache = self.session_secrets_cache.lock().unwrap();
        cache.get(session_id).cloned()
    }
}
