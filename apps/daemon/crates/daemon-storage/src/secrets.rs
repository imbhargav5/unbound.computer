//! High-level API for managing secrets.

use crate::{SecureStorage, StorageKeys, StorageResult};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use sha2::Sha256;

/// Supabase session metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SupabaseSessionMeta {
    /// User ID from Supabase Auth
    pub user_id: String,
    /// User email from Supabase Auth
    #[serde(default)]
    pub email: Option<String>,
    /// When the access token expires (ISO timestamp)
    pub expires_at: String,
    /// Project reference for namespacing
    pub project_ref: String,
}

/// Trusted device information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrustedDevice {
    /// Device UUID from the database
    pub device_id: String,
    /// Device name for display
    pub name: String,
    /// Device's long-term X25519 public key (base64)
    pub public_key: String,
    /// Device role in trust hierarchy
    pub role: TrustRole,
    /// When trust was established
    pub trusted_at: String,
    /// When trust expires (optional)
    pub expires_at: Option<String>,
}

/// Device role in trust hierarchy
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum TrustRole {
    TrustRoot,
    TrustedExecutor,
    TemporaryViewer,
}

/// High-level API for storing and retrieving secrets
pub struct SecretsManager {
    storage: Box<dyn SecureStorage>,
}

impl SecretsManager {
    /// Create a new secrets manager with the given storage backend
    pub fn new(storage: Box<dyn SecureStorage>) -> Self {
        Self { storage }
    }

    // ==========================================
    // Device Identity
    // ==========================================

    /// Get the user-scoped device private key name for a given user ID.
    /// Format matches macOS app: `com.unbound.device.privateKey.<userId>`
    fn user_scoped_device_key(user_id: &str) -> String {
        format!("com.unbound.device.privateKey.{}", user_id)
    }

    /// Store the device ID
    pub fn set_device_id(&self, device_id: &str) -> StorageResult<()> {
        self.storage.set(StorageKeys::DEVICE_ID, device_id)
    }

    /// Retrieve the device ID
    pub fn get_device_id(&self) -> StorageResult<Option<String>> {
        self.storage.get(StorageKeys::DEVICE_ID)
    }

    /// Store the device private key.
    ///
    /// If a Supabase session exists, stores as user-scoped key (macOS app compatible).
    /// Otherwise stores as legacy global key.
    pub fn set_device_private_key(&self, private_key: &[u8]) -> StorageResult<()> {
        let encoded = BASE64.encode(private_key);

        // Use user-scoped key if we have a session
        if let Ok(Some(meta)) = self.get_supabase_session_meta() {
            let key = Self::user_scoped_device_key(&meta.user_id);
            tracing::debug!("Storing device private key with user-scoped key for user {}", meta.user_id);
            return self.storage.set(&key, &encoded);
        }

        // Fallback to legacy global key
        tracing::debug!("Storing device private key with legacy global key");
        self.storage.set(StorageKeys::DEVICE_PRIVATE_KEY, &encoded)
    }

    /// Store device private key for a specific user ID.
    ///
    /// This is useful when setting up a new session and the user_id is known
    /// but session metadata isn't stored yet.
    pub fn set_device_private_key_for_user(&self, user_id: &str, private_key: &[u8]) -> StorageResult<()> {
        let key = Self::user_scoped_device_key(user_id);
        tracing::debug!("Storing device private key for user {}", user_id);
        self.storage.set(&key, &BASE64.encode(private_key))
    }

    /// Retrieve the device private key.
    ///
    /// This method tries multiple key locations for compatibility:
    /// 1. User-scoped key from macOS app: `com.unbound.device.privateKey.<userId>`
    /// 2. Legacy global key: `device_private_key`
    ///
    /// The key can be stored as either:
    /// - Raw binary (32 bytes, as stored by macOS app)
    /// - Base64-encoded string (as stored by daemon)
    pub fn get_device_private_key(&self) -> StorageResult<Option<Vec<u8>>> {
        // First, try the user-scoped key if we have session metadata
        if let Ok(Some(meta)) = self.get_supabase_session_meta() {
            let user_scoped_key = Self::user_scoped_device_key(&meta.user_id);
            tracing::debug!("Looking for user-scoped device key: {}", user_scoped_key);
            if let Some(bytes) = self.get_device_key_bytes(&user_scoped_key)? {
                tracing::info!("Found user-scoped device private key for user {}", meta.user_id);
                return Ok(Some(bytes));
            }
            tracing::debug!("User-scoped device key not found for known user");
        } else {
            tracing::debug!("No session meta available");
        }

        // Fallback to legacy global key
        if let Some(bytes) = self.get_device_key_bytes(StorageKeys::DEVICE_PRIVATE_KEY)? {
            tracing::debug!("Found legacy device private key");
            return Ok(Some(bytes));
        }

        tracing::debug!("No device private key found");
        Ok(None)
    }

    /// Helper to get device key bytes, handling both raw binary and base64 encoding.
    fn get_device_key_bytes(&self, key: &str) -> StorageResult<Option<Vec<u8>>> {
        // Try to get as raw bytes first (macOS app stores raw binary)
        if let Some(bytes) = self.storage.get_bytes(key)? {
            // Check if it looks like raw 32-byte key (X25519 private key)
            if bytes.len() == 32 {
                tracing::debug!("Device key is raw 32-byte binary");
                return Ok(Some(bytes));
            }

            // Check if it's base64-encoded (daemon stores base64)
            // Try to decode as UTF-8 first, then base64
            if let Ok(str_value) = String::from_utf8(bytes.clone()) {
                if let Ok(decoded) = BASE64.decode(&str_value) {
                    if decoded.len() == 32 {
                        tracing::debug!("Device key is base64-encoded");
                        return Ok(Some(decoded));
                    }
                }
            }

            // If it's not 32 bytes and not valid base64, it might be corrupted
            // but let's return it anyway and let the caller handle it
            tracing::warn!("Device key has unexpected format (len={}), returning as-is", bytes.len());
            return Ok(Some(bytes));
        }

        Ok(None)
    }

    /// Retrieve device private key for a specific user ID.
    ///
    /// Useful when you know the user_id but session metadata isn't available.
    pub fn get_device_private_key_for_user(&self, user_id: &str) -> StorageResult<Option<Vec<u8>>> {
        let key = Self::user_scoped_device_key(user_id);
        match self.storage.get(&key)? {
            Some(value) => {
                let bytes = BASE64
                    .decode(&value)
                    .map_err(|e| crate::StorageError::Encoding(e.to_string()))?;
                Ok(Some(bytes))
            }
            None => Ok(None),
        }
    }

    /// Generate a new device private key (32 bytes random).
    /// This is used when no device key exists (e.g., CLI-only usage without macOS app onboarding).
    pub fn generate_device_private_key() -> Vec<u8> {
        use rand::RngCore;
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        bytes.to_vec()
    }

    /// Ensure a device private key exists, generating one if needed.
    /// Returns the key (existing or newly generated).
    ///
    /// Uses user-scoped key storage when a Supabase session exists.
    pub fn ensure_device_private_key(&self) -> StorageResult<Vec<u8>> {
        if let Some(key) = self.get_device_private_key()? {
            return Ok(key);
        }

        // Generate and store a new key (will be user-scoped if session exists)
        let key = Self::generate_device_private_key();
        self.set_device_private_key(&key)?;
        tracing::info!("Generated new device private key");
        Ok(key)
    }

    /// Derive database encryption key from device private key using HKDF.
    /// This matches the macOS app's `SecureEnclaveKeyService.getDatabaseEncryptionKey()`.
    ///
    /// Returns a 32-byte key suitable for ChaCha20-Poly1305 encryption.
    pub fn get_database_encryption_key(&self) -> StorageResult<Option<[u8; 32]>> {
        let device_key = match self.get_device_private_key()? {
            Some(key) => key,
            None => return Ok(None),
        };

        // Use HKDF to derive database encryption key
        // Must match macOS app: context = "unbound-database-encryption-v1", empty salt
        let hkdf = Hkdf::<Sha256>::new(None, &device_key);
        let info = b"unbound-database-encryption-v1";
        let mut okm = [0u8; 32];
        hkdf.expand(info, &mut okm)
            .map_err(|e| crate::StorageError::Encoding(format!("HKDF expand failed: {:?}", e)))?;

        Ok(Some(okm))
    }

    // ==========================================
    // API Key
    // ==========================================

    /// Store the API key
    pub fn set_api_key(&self, api_key: &str) -> StorageResult<()> {
        self.storage.set(StorageKeys::API_KEY, api_key)
    }

    /// Retrieve the API key
    pub fn get_api_key(&self) -> StorageResult<Option<String>> {
        self.storage.get(StorageKeys::API_KEY)
    }

    /// Check if API key exists
    pub fn has_api_key(&self) -> StorageResult<bool> {
        self.storage.has(StorageKeys::API_KEY)
    }

    /// Delete the API key
    pub fn delete_api_key(&self) -> StorageResult<bool> {
        self.storage.delete(StorageKeys::API_KEY)
    }

    // ==========================================
    // Supabase Session
    // ==========================================

    /// Store Supabase access token
    pub fn set_supabase_access_token(&self, token: &str) -> StorageResult<()> {
        self.storage.set(StorageKeys::SUPABASE_ACCESS_TOKEN, token)
    }

    /// Retrieve Supabase access token
    pub fn get_supabase_access_token(&self) -> StorageResult<Option<String>> {
        self.storage.get(StorageKeys::SUPABASE_ACCESS_TOKEN)
    }

    /// Store Supabase refresh token
    pub fn set_supabase_refresh_token(&self, token: &str) -> StorageResult<()> {
        self.storage.set(StorageKeys::SUPABASE_REFRESH_TOKEN, token)
    }

    /// Retrieve Supabase refresh token
    pub fn get_supabase_refresh_token(&self) -> StorageResult<Option<String>> {
        self.storage.get(StorageKeys::SUPABASE_REFRESH_TOKEN)
    }

    /// Store Supabase session metadata
    pub fn set_supabase_session_meta(&self, meta: &SupabaseSessionMeta) -> StorageResult<()> {
        let json = serde_json::to_string(meta)
            .map_err(|e| crate::StorageError::Encoding(e.to_string()))?;
        self.storage.set(StorageKeys::SUPABASE_SESSION_META, &json)
    }

    /// Retrieve Supabase session metadata
    pub fn get_supabase_session_meta(&self) -> StorageResult<Option<SupabaseSessionMeta>> {
        match self.storage.get(StorageKeys::SUPABASE_SESSION_META)? {
            Some(json) => {
                let meta: SupabaseSessionMeta = serde_json::from_str(&json)
                    .map_err(|e| crate::StorageError::Encoding(e.to_string()))?;
                Ok(Some(meta))
            }
            None => Ok(None),
        }
    }

    /// Check if Supabase session exists
    pub fn has_supabase_session(&self) -> StorageResult<bool> {
        let has_token = self.storage.has(StorageKeys::SUPABASE_ACCESS_TOKEN)?;
        let has_meta = self.storage.has(StorageKeys::SUPABASE_SESSION_META)?;
        Ok(has_token && has_meta)
    }

    /// Check if Supabase session is expired
    pub fn is_supabase_session_expired(&self) -> StorageResult<bool> {
        match self.get_supabase_session_meta()? {
            Some(meta) => {
                let expires_at = chrono::DateTime::parse_from_rfc3339(&meta.expires_at)
                    .map_err(|e| crate::StorageError::Encoding(e.to_string()))?;
                let now = chrono::Utc::now();
                // Consider expired if less than 60 seconds remaining
                Ok(expires_at.signed_duration_since(now).num_seconds() < 60)
            }
            None => Ok(true),
        }
    }

    /// Store complete Supabase session (tokens + metadata)
    pub fn set_supabase_session(
        &self,
        access_token: &str,
        refresh_token: &str,
        user_id: &str,
        email: Option<&str>,
        expires_at: &str,
    ) -> StorageResult<()> {
        self.set_supabase_access_token(access_token)?;
        self.set_supabase_refresh_token(refresh_token)?;
        self.set_supabase_session_meta(&SupabaseSessionMeta {
            user_id: user_id.to_string(),
            email: email.map(String::from),
            expires_at: expires_at.to_string(),
            project_ref: "default".to_string(),
        })?;
        Ok(())
    }

    /// Clear Supabase session
    pub fn clear_supabase_session(&self) -> StorageResult<()> {
        let _ = self.storage.delete(StorageKeys::SUPABASE_ACCESS_TOKEN);
        let _ = self.storage.delete(StorageKeys::SUPABASE_REFRESH_TOKEN);
        let _ = self.storage.delete(StorageKeys::SUPABASE_SESSION_META);
        Ok(())
    }

    // ==========================================
    // Trusted Devices
    // ==========================================

    /// Get all trusted devices
    pub fn get_trusted_devices(&self) -> StorageResult<Vec<TrustedDevice>> {
        match self.storage.get(StorageKeys::TRUSTED_DEVICES)? {
            Some(json) => {
                let devices: Vec<TrustedDevice> = serde_json::from_str(&json)
                    .map_err(|e| crate::StorageError::Encoding(e.to_string()))?;
                Ok(devices)
            }
            None => Ok(Vec::new()),
        }
    }

    /// Add a trusted device
    pub fn add_trusted_device(&self, device: TrustedDevice) -> StorageResult<()> {
        let mut devices = self.get_trusted_devices()?;
        devices.retain(|d| d.device_id != device.device_id);
        devices.push(device);
        let json = serde_json::to_string(&devices)
            .map_err(|e| crate::StorageError::Encoding(e.to_string()))?;
        self.storage.set(StorageKeys::TRUSTED_DEVICES, &json)
    }

    /// Remove a trusted device
    pub fn remove_trusted_device(&self, device_id: &str) -> StorageResult<bool> {
        let mut devices = self.get_trusted_devices()?;
        let original_len = devices.len();
        devices.retain(|d| d.device_id != device_id);
        if devices.len() == original_len {
            return Ok(false);
        }
        let json = serde_json::to_string(&devices)
            .map_err(|e| crate::StorageError::Encoding(e.to_string()))?;
        self.storage.set(StorageKeys::TRUSTED_DEVICES, &json)?;
        Ok(true)
    }

    // ==========================================
    // Session Secrets (for message encryption)
    // ==========================================

    /// Get a session secret from keychain
    /// Uses the same key pattern as macOS app: com.unbound.session.secret.<sessionId>
    pub fn get_session_secret(&self, session_id: &str) -> StorageResult<Option<String>> {
        let key = format!("com.unbound.session.secret.{}", session_id);
        self.storage.get(&key)
    }

    /// Store a session secret in keychain
    pub fn set_session_secret(&self, session_id: &str, secret: &str) -> StorageResult<()> {
        let key = format!("com.unbound.session.secret.{}", session_id);
        self.storage.set(&key, secret)
    }

    /// Delete a session secret from keychain
    pub fn delete_session_secret(&self, session_id: &str) -> StorageResult<bool> {
        let key = format!("com.unbound.session.secret.{}", session_id);
        self.storage.delete(&key)
    }

    /// Generate a new session secret
    /// Format: sess_<base64url(32 bytes)>
    pub fn generate_session_secret() -> String {
        use rand::RngCore;
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        let base64url = BASE64.encode(bytes)
            .replace('+', "-")
            .replace('/', "_")
            .replace('=', "");
        format!("sess_{}", base64url)
    }

    /// Parse session secret to get raw key bytes
    pub fn parse_session_secret(secret: &str) -> StorageResult<Vec<u8>> {
        if !secret.starts_with("sess_") {
            return Err(crate::StorageError::Encoding("Invalid session secret format".to_string()));
        }
        let base64url = &secret[5..];
        let base64 = base64url
            .replace('-', "+")
            .replace('_', "/");
        // Add padding
        let padded = match base64.len() % 4 {
            2 => format!("{}==", base64),
            3 => format!("{}=", base64),
            _ => base64,
        };
        BASE64.decode(&padded)
            .map_err(|e| crate::StorageError::Encoding(e.to_string()))
    }

    // ==========================================
    // Clear All
    // ==========================================

    /// Clear all stored secrets
    pub fn clear_all(&self) -> StorageResult<()> {
        let _ = self.storage.delete(StorageKeys::MASTER_KEY);
        let _ = self.storage.delete(StorageKeys::DEVICE_ID);
        let _ = self.storage.delete(StorageKeys::DEVICE_PRIVATE_KEY);
        let _ = self.storage.delete(StorageKeys::API_KEY);
        let _ = self.storage.delete(StorageKeys::TRUSTED_DEVICES);
        let _ = self.storage.delete(StorageKeys::SUPABASE_ACCESS_TOKEN);
        let _ = self.storage.delete(StorageKeys::SUPABASE_REFRESH_TOKEN);
        let _ = self.storage.delete(StorageKeys::SUPABASE_SESSION_META);
        Ok(())
    }
}
