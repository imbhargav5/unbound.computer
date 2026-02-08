//! Session secret in-memory cache.
//!
//! Provides fast access to session encryption keys by caching them in memory.
//! Falls back to SQLite and keychain when not cached.

use daemon_database::queries;
use daemon_storage::SecretsManager;
use rusqlite::Connection;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tracing::debug;

/// Thread-safe session secret cache.
#[derive(Clone)]
pub struct SessionSecretCache {
    /// In-memory cache: session_id -> decrypted key bytes
    cache: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

impl SessionSecretCache {
    /// Create a new empty cache.
    pub fn new() -> Self {
        Self {
            cache: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Create from an existing shared cache (for DaemonState compatibility).
    pub fn from_shared(cache: Arc<Mutex<HashMap<String, Vec<u8>>>>) -> Self {
        Self { cache }
    }

    /// Get a session secret, checking cache first, then SQLite, then keychain.
    /// Automatically caches results from SQLite/keychain lookups.
    pub fn get(
        &self,
        conn: &Connection,
        secrets: &SecretsManager,
        session_id: &str,
        cached_db_key: Option<&[u8; 32]>,
    ) -> Option<Vec<u8>> {
        // 1. Check memory cache first (fastest path)
        {
            let cache = self.cache.lock().unwrap();
            if let Some(key) = cache.get(session_id) {
                debug!(session_id, "Session secret found in memory cache");
                return Some(key.clone());
            }
        }

        // 2. Try SQLite (session_secrets table)
        if let Some(key) = self.try_sqlite(conn, session_id, cached_db_key) {
            self.insert(session_id, key.clone());
            return Some(key);
        }

        // 3. Fall back to keychain (legacy)
        if let Some(key) = self.try_keychain(secrets, session_id) {
            self.insert(session_id, key.clone());
            return Some(key);
        }

        None
    }

    /// Insert a session secret into the cache.
    pub fn insert(&self, session_id: &str, key: Vec<u8>) {
        let mut cache = self.cache.lock().unwrap();
        cache.insert(session_id.to_string(), key);
        debug!(session_id, "Cached session secret in memory");
    }

    /// Remove a session secret from the cache.
    pub fn remove(&self, session_id: &str) -> Option<Vec<u8>> {
        let mut cache = self.cache.lock().unwrap();
        cache.remove(session_id)
    }

    /// Check if a session secret is cached.
    pub fn contains(&self, session_id: &str) -> bool {
        let cache = self.cache.lock().unwrap();
        cache.contains_key(session_id)
    }

    /// Get the number of cached secrets.
    pub fn len(&self) -> usize {
        let cache = self.cache.lock().unwrap();
        cache.len()
    }

    /// Check if the cache is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Clear all cached secrets.
    pub fn clear(&self) {
        let mut cache = self.cache.lock().unwrap();
        cache.clear();
    }

    /// Get the underlying shared cache for interoperability.
    /// Used to share the cache with other components (e.g., SessionSyncService).
    pub fn inner(&self) -> Arc<Mutex<HashMap<String, Vec<u8>>>> {
        self.cache.clone()
    }

    /// Try to get session secret from SQLite.
    fn try_sqlite(
        &self,
        conn: &Connection,
        session_id: &str,
        cached_db_key: Option<&[u8; 32]>,
    ) -> Option<Vec<u8>> {
        let db_key = cached_db_key?;
        let secret_record = queries::get_session_secret(conn, session_id).ok()??;

        let plaintext = daemon_database::decrypt_content(
            db_key,
            &secret_record.nonce,
            &secret_record.encrypted_secret,
        )
        .ok()?;

        let secret_str = String::from_utf8(plaintext).ok()?;
        let key = SecretsManager::parse_session_secret(&secret_str).ok()?;

        debug!(session_id, "Retrieved session secret from SQLite");
        Some(key)
    }

    /// Try to get session secret from keychain (legacy).
    fn try_keychain(&self, secrets: &SecretsManager, session_id: &str) -> Option<Vec<u8>> {
        let secret = secrets.get_session_secret(session_id).ok()??;
        let key = SecretsManager::parse_session_secret(&secret).ok()?;

        debug!(
            session_id,
            "Retrieved session secret from keychain (legacy)"
        );
        Some(key)
    }
}

impl Default for SessionSecretCache {
    fn default() -> Self {
        Self::new()
    }
}
