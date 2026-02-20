//! # Session Synchronization Service
//!
//! This module provides [`SessionSyncService`] for syncing local coding sessions
//! and their associated data to Supabase for cross-device access.
//!
//! ## Responsibilities
//!
//! - **Repository Sync**: Syncs repository metadata to Supabase (required before sessions)
//! - **Session Sync**: Syncs coding session metadata with status tracking
//! - **Secret Distribution**: Encrypts and distributes session secrets to all user devices
//!
//! ## Cross-Device Secret Sharing
//!
//! Session secrets are encrypted using hybrid encryption (ECDH + XChaCha20-Poly1305):
//!
//! ```text
//! ┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
//! │  Device A       │    │   Supabase   │    │   Device B      │
//! │  (Session Owner)│    │   (Cloud)    │    │   (Recipient)   │
//! └────────┬────────┘    └──────┬───────┘    └────────┬────────┘
//!          │                    │                     │
//!          │  Encrypt secret    │                     │
//!          │  for each device   │                     │
//!          │  public key        │                     │
//!          │                    │                     │
//!          │  ─────────────────▶│                     │
//!          │  Store encrypted   │                     │
//!          │  secrets           │                     │
//!          │                    │  ────────────────▶  │
//!          │                    │  Fetch & decrypt    │
//!          │                    │  with private key   │
//! ```
//!
//! ## Usage
//!
//! ```ignore
//! let service = SessionSyncService::new(
//!     supabase_client,
//!     db_pool,
//!     secrets_manager,
//!     device_id,
//!     device_private_key,
//!     secrets_cache,
//! );
//!
//! // Sync a new session (handles repository, session, and secrets)
//! service.sync_new_session(session_id, repository_id, session_secret).await?;
//! ```

use base64::Engine;
use daemon_database::{queries, AgentCodingSession, AsyncDatabase, Repository};
use daemon_storage::SecretsManager;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tracing::{debug, info, warn};
use ymir::{CodingSessionSecretRecord, SupabaseClient};

/// Base64 encoding engine for keys and encrypted data.
const BASE64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

/// Result type alias for sync operations.
pub type SyncResult<T> = Result<T, SyncError>;

/// Errors that can occur during session synchronization.
///
/// These errors indicate why a sync operation failed and help callers
/// decide whether to retry or handle the error differently.
#[derive(Debug)]
pub enum SyncError {
    /// User is not authenticated with Supabase.
    ///
    /// The user must log in before syncing. Check for valid access token.
    NotAuthenticated,

    /// Device identity has not been configured.
    ///
    /// Device registration must complete before syncing sessions.
    /// This includes generating and storing device keypair.
    NoDeviceIdentity,

    /// Referenced repository was not found in local database.
    ///
    /// The repository must exist locally before it can be synced.
    /// Contains the repository ID that was not found.
    RepositoryNotFound(String),

    /// Referenced session was not found in local database.
    SessionNotFound(String),

    /// Supabase API request failed.
    ///
    /// Could be network error, authentication expired, or server error.
    /// Contains the error message from the API.
    Supabase(String),

    /// Cryptographic operation failed.
    ///
    /// Could be key derivation, encryption, or encoding failure.
    /// Contains the error description.
    Encryption(String),
}

impl std::fmt::Display for SyncError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncError::NotAuthenticated => write!(f, "Not authenticated"),
            SyncError::NoDeviceIdentity => write!(f, "No device identity configured"),
            SyncError::RepositoryNotFound(id) => write!(f, "Repository not found: {}", id),
            SyncError::SessionNotFound(id) => write!(f, "Session not found: {}", id),
            SyncError::Supabase(msg) => write!(f, "Supabase error: {}", msg),
            SyncError::Encryption(msg) => write!(f, "Encryption error: {}", msg),
        }
    }
}

impl std::error::Error for SyncError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct RepositorySyncFields<'a> {
    remote_url: Option<&'a str>,
    default_branch: Option<&'a str>,
    is_worktree: bool,
    worktree_branch: Option<&'a str>,
}

fn repository_sync_fields(repo: &Repository) -> RepositorySyncFields<'_> {
    RepositorySyncFields {
        remote_url: repo.default_remote.as_deref(),
        default_branch: repo.default_branch.as_deref(),
        is_worktree: false,
        worktree_branch: None,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct SessionSyncFields<'a> {
    is_worktree: bool,
    worktree_path: Option<&'a str>,
}

fn session_sync_fields(session: &AgentCodingSession) -> SessionSyncFields<'_> {
    SessionSyncFields {
        is_worktree: session.is_worktree,
        worktree_path: session.worktree_path.as_deref(),
    }
}

/// Service for synchronizing sessions and secrets to Supabase.
///
/// Handles the complete lifecycle of syncing a coding session:
/// 1. Sync the repository (foreign key dependency)
/// 2. Sync the session metadata
/// 3. Distribute encrypted session secrets to all user devices
///
/// ## Thread Safety
///
/// All fields are wrapped in `Arc<Mutex<_>>` for safe concurrent access.
/// The service can be cloned and shared across async tasks.
///
/// ## Authentication
///
/// All operations require valid Supabase authentication. The service
/// retrieves credentials from [`SecretsManager`] and will fail with
/// [`SyncError::NotAuthenticated`] if not logged in.
pub struct SessionSyncService {
    /// Supabase HTTP client for API calls.
    supabase_client: Arc<SupabaseClient>,
    /// Async database for repository queries.
    db: AsyncDatabase,
    /// Secrets manager for authentication credentials.
    secrets: Arc<Mutex<SecretsManager>>,
    /// This device's unique identifier.
    device_id: Arc<Mutex<Option<String>>>,
    /// This device's private key for cryptographic operations.
    device_private_key: Arc<Mutex<Option<[u8; 32]>>>,
    /// In-memory cache of session secrets (for potential local fast access).
    #[allow(dead_code)]
    session_secrets_cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

impl SessionSyncService {
    /// Creates a new session sync service.
    ///
    /// # Arguments
    ///
    /// * `supabase_client` - Shared Supabase HTTP client
    /// * `db` - Database connection pool for local queries
    /// * `secrets` - Secrets manager for authentication credentials
    /// * `device_id` - This device's unique identifier
    /// * `device_private_key` - This device's X25519 private key for encryption
    /// * `session_secrets_cache` - Shared cache for session secrets
    ///
    /// # Returns
    ///
    /// A new `SessionSyncService` instance ready to sync sessions.
    pub fn new(
        supabase_client: Arc<SupabaseClient>,
        db: AsyncDatabase,
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

    /// Retrieves authentication context required for Supabase API calls.
    ///
    /// Collects all necessary identifiers and tokens:
    /// - `user_id`: The authenticated user's Supabase ID
    /// - `device_id`: This device's unique identifier
    /// - `access_token`: Current Supabase JWT access token
    ///
    /// # Returns
    ///
    /// A tuple of `(user_id, device_id, access_token)`.
    ///
    /// # Errors
    ///
    /// - [`SyncError::NotAuthenticated`] if no valid session exists
    /// - [`SyncError::NoDeviceIdentity`] if device ID is not set
    /// - [`SyncError::Supabase`] if secrets manager fails
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

    /// Syncs a repository to Supabase.
    ///
    /// Uploads repository metadata to the cloud for cross-device visibility.
    /// This must be called before syncing any sessions that reference this
    /// repository (foreign key constraint).
    ///
    /// # Arguments
    ///
    /// * `repository_id` - UUID of the local repository to sync
    ///
    /// # Errors
    ///
    /// - [`SyncError::NotAuthenticated`] if user is not logged in
    /// - [`SyncError::NoDeviceIdentity`] if device is not registered
    /// - [`SyncError::RepositoryNotFound`] if repository doesn't exist locally
    /// - [`SyncError::Supabase`] if API call fails
    pub async fn sync_repository(&self, repository_id: &str) -> SyncResult<()> {
        let (user_id, device_id, access_token) = self.get_auth_context()?;

        // Get repository from local database
        let repo_id_owned = repository_id.to_string();
        let repo = self
            .db
            .call(move |conn| queries::get_repository(conn, &repo_id_owned))
            .await
            .map_err(|e| SyncError::Supabase(e.to_string()))?
            .ok_or_else(|| SyncError::RepositoryNotFound(repository_id.to_string()))?;
        let sync_fields = repository_sync_fields(&repo);

        self.supabase_client
            .upsert_repository(
                &repo.id,
                &user_id,
                &device_id,
                &repo.name,
                &repo.path,
                sync_fields.remote_url,
                sync_fields.default_branch,
                sync_fields.is_worktree,
                sync_fields.worktree_branch,
                &access_token,
            )
            .await
            .map_err(|e| SyncError::Supabase(e.to_string()))?;

        debug!(repository_id = %repository_id, "Repository synced to Supabase");
        Ok(())
    }

    /// Syncs a coding session to Supabase.
    ///
    /// Uploads session metadata with current status. The referenced repository
    /// must already exist in Supabase (call [`sync_repository`](Self::sync_repository) first).
    ///
    /// # Arguments
    ///
    /// * `session_id` - UUID of the coding session
    /// * `repository_id` - UUID of the parent repository
    /// * `status` - Current session status (e.g., "active", "completed")
    ///
    /// # Errors
    ///
    /// - [`SyncError::NotAuthenticated`] if user is not logged in
    /// - [`SyncError::NoDeviceIdentity`] if device is not registered
    /// - [`SyncError::Supabase`] if API call fails (including FK violation)
    pub async fn sync_session(
        &self,
        session_id: &str,
        repository_id: &str,
        status: &str,
    ) -> SyncResult<()> {
        let (user_id, device_id, access_token) = self.get_auth_context()?;
        let session_id_owned = session_id.to_string();
        let session = self
            .db
            .call(move |conn| queries::get_session(conn, &session_id_owned))
            .await
            .map_err(|e| SyncError::Supabase(e.to_string()))?
            .ok_or_else(|| SyncError::SessionNotFound(session_id.to_string()))?;
        let sync_fields = session_sync_fields(&session);

        if session.repository_id != repository_id {
            warn!(
                session_id = %session_id,
                requested_repository_id = %repository_id,
                actual_repository_id = %session.repository_id,
                "sync_session repository_id did not match local session record; using local value"
            );
        }

        self.supabase_client
            .upsert_coding_session(
                session_id,
                &user_id,
                &device_id,
                &session.repository_id,
                status,
                Some(session.title.as_str()),
                None, // current_branch
                None, // working_directory
                sync_fields.is_worktree,
                sync_fields.worktree_path,
                &access_token,
            )
            .await
            .map_err(|e| SyncError::Supabase(e.to_string()))?;

        info!(session_id = %session_id, "Session synced to Supabase");
        Ok(())
    }

    /// Distributes a session secret to all user devices.
    ///
    /// Enables cross-device access by encrypting the session secret for each
    /// device's public key and storing the encrypted secrets in Supabase.
    ///
    /// ## Encryption Process
    ///
    /// For each device (including this one):
    /// 1. Generate ephemeral X25519 keypair
    /// 2. Perform ECDH with device's public key
    /// 3. Derive symmetric key using HKDF
    /// 4. Encrypt secret with XChaCha20-Poly1305
    /// 5. Store ephemeral public key + ciphertext in Supabase
    ///
    /// This provides forward secrecy - compromise of a device's private key
    /// doesn't reveal secrets encrypted with previous ephemeral keys.
    ///
    /// # Arguments
    ///
    /// * `session_id` - UUID of the coding session
    /// * `session_secret` - The plaintext session secret to distribute
    ///
    /// # Returns
    ///
    /// The number of devices the secret was successfully distributed to.
    ///
    /// # Errors
    ///
    /// - [`SyncError::NotAuthenticated`] if user is not logged in
    /// - [`SyncError::NoDeviceIdentity`] if device private key is not available
    /// - [`SyncError::Encryption`] if encryption fails for this device
    /// - [`SyncError::Supabase`] if fetching devices or storing secrets fails
    ///
    /// # Notes
    ///
    /// Encryption failures for other devices are logged and skipped (not fatal).
    /// This ensures a single misconfigured device doesn't block the entire operation.
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
            daemon_config_and_utils::hybrid_crypto::public_key_from_private(&device_private_key);

        let (ephemeral_pub, encrypted) = daemon_config_and_utils::encrypt_for_device(
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

            let (ephemeral_pub, encrypted) = match daemon_config_and_utils::encrypt_for_device(
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

    /// Syncs a new session with all associated data.
    ///
    /// This is the **main entry point** for syncing a newly created session.
    /// It orchestrates the complete sync process in the correct order:
    ///
    /// 1. **Repository sync** - Ensures the parent repository exists in Supabase
    /// 2. **Session sync** - Creates/updates the session record with "active" status
    /// 3. **Secret distribution** - Encrypts and shares secrets with all devices
    ///
    /// ## Error Handling
    ///
    /// This method is resilient - failures in early steps don't prevent later steps:
    /// - If repository sync fails, session sync is still attempted (repo may already exist)
    /// - If session sync fails, secret distribution is still attempted
    /// - Errors are logged as warnings but the method returns `Ok(())` to not block callers
    ///
    /// # Arguments
    ///
    /// * `session_id` - UUID of the coding session to sync
    /// * `repository_id` - UUID of the parent repository
    /// * `session_secret` - The session's symmetric encryption key to distribute
    ///
    /// # Returns
    ///
    /// Always returns `Ok(())` - check logs for any sync failures.
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

    /// Caches a session secret in memory for fast local access.
    ///
    /// Useful for avoiding repeated decryption when accessing the same
    /// session secret multiple times.
    ///
    /// # Arguments
    ///
    /// * `session_id` - UUID of the coding session
    /// * `secret_key` - The decrypted 32-byte symmetric key
    #[allow(dead_code)]
    pub fn cache_secret(&self, session_id: &str, secret_key: Vec<u8>) {
        let mut cache = self.session_secrets_cache.lock().unwrap();
        cache.insert(session_id.to_string(), secret_key);
    }

    /// Retrieves a cached session secret if available.
    ///
    /// # Arguments
    ///
    /// * `session_id` - UUID of the coding session
    ///
    /// # Returns
    ///
    /// The cached secret key, or `None` if not in cache.
    #[allow(dead_code)]
    pub fn get_cached_secret(&self, session_id: &str) -> Option<Vec<u8>> {
        let cache = self.session_secrets_cache.lock().unwrap();
        cache.get(session_id).cloned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use daemon_storage::SecureStorage;

    // ========================================================================
    // In-memory storage for tests (SecureStorage impl)
    // ========================================================================

    struct MemoryStorage {
        data: std::sync::Mutex<std::collections::HashMap<String, String>>,
    }

    impl MemoryStorage {
        fn new() -> Self {
            Self {
                data: std::sync::Mutex::new(std::collections::HashMap::new()),
            }
        }
    }

    impl SecureStorage for MemoryStorage {
        fn set(&self, key: &str, value: &str) -> daemon_storage::StorageResult<()> {
            self.data
                .lock()
                .unwrap()
                .insert(key.to_string(), value.to_string());
            Ok(())
        }

        fn get(&self, key: &str) -> daemon_storage::StorageResult<Option<String>> {
            Ok(self.data.lock().unwrap().get(key).cloned())
        }

        fn delete(&self, key: &str) -> daemon_storage::StorageResult<bool> {
            Ok(self.data.lock().unwrap().remove(key).is_some())
        }
    }

    fn make_secrets_manager() -> SecretsManager {
        SecretsManager::new(Box::new(MemoryStorage::new()))
    }

    // ========================================================================
    // SyncError Display tests
    // ========================================================================

    #[test]
    fn sync_error_display_not_authenticated() {
        let err = SyncError::NotAuthenticated;
        assert_eq!(err.to_string(), "Not authenticated");
    }

    #[test]
    fn sync_error_display_no_device_identity() {
        let err = SyncError::NoDeviceIdentity;
        assert_eq!(err.to_string(), "No device identity configured");
    }

    #[test]
    fn sync_error_display_repository_not_found() {
        let err = SyncError::RepositoryNotFound("repo-123".to_string());
        assert_eq!(err.to_string(), "Repository not found: repo-123");
    }

    #[test]
    fn sync_error_display_session_not_found() {
        let err = SyncError::SessionNotFound("session-123".to_string());
        assert_eq!(err.to_string(), "Session not found: session-123");
    }

    #[test]
    fn sync_error_display_supabase() {
        let err = SyncError::Supabase("connection refused".to_string());
        assert_eq!(err.to_string(), "Supabase error: connection refused");
    }

    #[test]
    fn sync_error_display_encryption() {
        let err = SyncError::Encryption("bad key".to_string());
        assert_eq!(err.to_string(), "Encryption error: bad key");
    }

    #[test]
    fn sync_error_is_error_trait() {
        let err: Box<dyn std::error::Error> = Box::new(SyncError::NotAuthenticated);
        assert_eq!(err.to_string(), "Not authenticated");
    }

    #[test]
    fn sync_error_debug_includes_variant() {
        let err = SyncError::RepositoryNotFound("abc".to_string());
        let debug_str = format!("{:?}", err);
        assert!(debug_str.contains("RepositoryNotFound"));
        assert!(debug_str.contains("abc"));
    }

    // ========================================================================
    // Sync metadata projection tests
    // ========================================================================

    #[test]
    fn repository_sync_fields_use_local_default_branch_and_remote() {
        let now = chrono::Utc::now();
        let repo = Repository {
            id: "repo-1".to_string(),
            path: "/tmp/repo".to_string(),
            name: "repo".to_string(),
            last_accessed_at: now,
            added_at: now,
            is_git_repository: true,
            sessions_path: Some("/tmp/repo/.unbound/worktrees".to_string()),
            default_branch: Some("main".to_string()),
            default_remote: Some("origin".to_string()),
            created_at: now,
            updated_at: now,
        };

        let fields = repository_sync_fields(&repo);
        assert_eq!(fields.remote_url, Some("origin"));
        assert_eq!(fields.default_branch, Some("main"));
        assert!(!fields.is_worktree);
        assert_eq!(fields.worktree_branch, None);
    }

    #[test]
    fn session_sync_fields_use_local_worktree_metadata() {
        let now = chrono::Utc::now();
        let session = AgentCodingSession {
            id: "session-1".to_string(),
            repository_id: "repo-1".to_string(),
            title: "Session".to_string(),
            claude_session_id: None,
            status: daemon_database::SessionStatus::Active,
            is_worktree: true,
            worktree_path: Some("/tmp/repo/.unbound/worktrees/session-1".to_string()),
            created_at: now,
            last_accessed_at: now,
            updated_at: now,
        };

        let fields = session_sync_fields(&session);
        assert!(fields.is_worktree);
        assert_eq!(
            fields.worktree_path,
            Some("/tmp/repo/.unbound/worktrees/session-1")
        );
    }

    // ========================================================================
    // Session secret cache tests
    // ========================================================================

    #[test]
    fn cache_secret_and_retrieve() {
        let cache = Arc::new(Mutex::new(HashMap::new()));
        cache
            .lock()
            .unwrap()
            .insert("session-1".to_string(), vec![1, 2, 3, 4]);

        let result = cache.lock().unwrap().get("session-1").cloned();
        assert_eq!(result, Some(vec![1, 2, 3, 4]));
    }

    #[test]
    fn cache_secret_overwrites_existing() {
        let cache: Arc<Mutex<HashMap<String, Vec<u8>>>> = Arc::new(Mutex::new(HashMap::new()));

        cache
            .lock()
            .unwrap()
            .insert("session-1".to_string(), vec![1, 2, 3]);
        cache
            .lock()
            .unwrap()
            .insert("session-1".to_string(), vec![4, 5, 6]);

        let result = cache.lock().unwrap().get("session-1").cloned();
        assert_eq!(result, Some(vec![4, 5, 6]));
    }

    #[test]
    fn cache_secret_independent_sessions() {
        let cache: Arc<Mutex<HashMap<String, Vec<u8>>>> = Arc::new(Mutex::new(HashMap::new()));

        cache
            .lock()
            .unwrap()
            .insert("session-1".to_string(), vec![1, 2, 3]);
        cache
            .lock()
            .unwrap()
            .insert("session-2".to_string(), vec![4, 5, 6]);

        assert_eq!(
            cache.lock().unwrap().get("session-1").cloned(),
            Some(vec![1, 2, 3])
        );
        assert_eq!(
            cache.lock().unwrap().get("session-2").cloned(),
            Some(vec![4, 5, 6])
        );
        assert!(cache.lock().unwrap().get("session-3").is_none());
    }

    // ========================================================================
    // get_auth_context tests
    // ========================================================================

    #[test]
    fn get_auth_context_fails_without_session() {
        let supabase_client = Arc::new(ymir::SupabaseClient::new(
            "http://localhost:54321",
            "test-key",
        ));
        let secrets = Arc::new(Mutex::new(make_secrets_manager()));
        let device_id = Arc::new(Mutex::new(Some("device-1".to_string())));
        let device_private_key = Arc::new(Mutex::new(Some([42u8; 32])));
        let cache = Arc::new(Mutex::new(HashMap::new()));

        // Need a real AsyncDatabase — create via temp file
        let tmp = std::env::temp_dir().join(format!("levi_test_{}.db", std::process::id()));
        let rt = tokio::runtime::Runtime::new().unwrap();
        let db = rt
            .block_on(daemon_database::AsyncDatabase::open(&tmp))
            .unwrap();

        let service = SessionSyncService::new(
            supabase_client,
            db,
            secrets,
            device_id,
            device_private_key,
            cache,
        );

        // SecretsManager has no session stored → NotAuthenticated
        let err = service.get_auth_context().unwrap_err();
        assert!(matches!(err, SyncError::NotAuthenticated));

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn get_auth_context_fails_without_device_id() {
        let supabase_client = Arc::new(ymir::SupabaseClient::new(
            "http://localhost:54321",
            "test-key",
        ));
        let secrets = Arc::new(Mutex::new(make_secrets_manager()));
        let device_id = Arc::new(Mutex::new(None)); // No device ID
        let device_private_key = Arc::new(Mutex::new(Some([42u8; 32])));
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let tmp = std::env::temp_dir().join(format!("levi_test_nd_{}.db", std::process::id()));
        let rt = tokio::runtime::Runtime::new().unwrap();
        let db = rt
            .block_on(daemon_database::AsyncDatabase::open(&tmp))
            .unwrap();

        // Store a fake session so we get past the auth check
        {
            let sm = secrets.lock().unwrap();
            sm.set_supabase_session(
                "fake-access",
                "fake-refresh",
                "user-1",
                Some("test@example.com"),
                "2099-01-01T00:00:00Z",
            )
            .unwrap();
        }

        let service = SessionSyncService::new(
            supabase_client,
            db,
            secrets,
            device_id,
            device_private_key,
            cache,
        );

        let err = service.get_auth_context().unwrap_err();
        assert!(matches!(err, SyncError::NoDeviceIdentity));

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn get_auth_context_succeeds_with_valid_state() {
        let supabase_client = Arc::new(ymir::SupabaseClient::new(
            "http://localhost:54321",
            "test-key",
        ));
        let secrets = Arc::new(Mutex::new(make_secrets_manager()));
        let device_id = Arc::new(Mutex::new(Some("device-42".to_string())));
        let device_private_key = Arc::new(Mutex::new(Some([42u8; 32])));
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let tmp = std::env::temp_dir().join(format!("levi_test_ok_{}.db", std::process::id()));
        let rt = tokio::runtime::Runtime::new().unwrap();
        let db = rt
            .block_on(daemon_database::AsyncDatabase::open(&tmp))
            .unwrap();

        {
            let sm = secrets.lock().unwrap();
            sm.set_supabase_session(
                "my-access-token",
                "my-refresh-token",
                "user-99",
                Some("user@example.com"),
                "2099-01-01T00:00:00Z",
            )
            .unwrap();
        }

        let service = SessionSyncService::new(
            supabase_client,
            db,
            secrets,
            device_id,
            device_private_key,
            cache,
        );

        let (user_id, device_id, access_token) = service.get_auth_context().unwrap();
        assert_eq!(user_id, "user-99");
        assert_eq!(device_id, "device-42");
        assert_eq!(access_token, "my-access-token");

        let _ = std::fs::remove_file(&tmp);
    }

    // ========================================================================
    // distribute_secret tests (partial — requires no network)
    // ========================================================================

    #[test]
    fn distribute_secret_fails_without_device_private_key() {
        let supabase_client = Arc::new(ymir::SupabaseClient::new(
            "http://localhost:54321",
            "test-key",
        ));
        let secrets = Arc::new(Mutex::new(make_secrets_manager()));
        let device_id = Arc::new(Mutex::new(Some("device-1".to_string())));
        let device_private_key = Arc::new(Mutex::new(None)); // No private key
        let cache = Arc::new(Mutex::new(HashMap::new()));

        let tmp = std::env::temp_dir().join(format!("levi_test_dpk_{}.db", std::process::id()));
        let rt = tokio::runtime::Runtime::new().unwrap();
        let db = rt
            .block_on(daemon_database::AsyncDatabase::open(&tmp))
            .unwrap();

        {
            let sm = secrets.lock().unwrap();
            sm.set_supabase_session(
                "token",
                "refresh",
                "user-1",
                Some("test@example.com"),
                "2099-01-01T00:00:00Z",
            )
            .unwrap();
        }

        let service = SessionSyncService::new(
            supabase_client,
            db,
            secrets,
            device_id,
            device_private_key,
            cache,
        );

        let result = rt.block_on(service.distribute_secret("session-1", "secret-val"));
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), SyncError::NoDeviceIdentity));

        let _ = std::fs::remove_file(&tmp);
    }
}
