//! High-level API for managing secrets.

use crate::{SecureStorage, StorageKeys, StorageResult};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use hkdf::Hkdf;
use sha2::Sha256;

/// High-level API for storing and retrieving secrets
pub struct SecretsManager {
    storage: Box<dyn SecureStorage>,
}

impl SecretsManager {
    /// Create a new secrets manager with the given storage backend
    pub fn new(storage: Box<dyn SecureStorage>) -> Self {
        Self { storage }
    }

    /// Store the device ID
    pub fn set_device_id(&self, device_id: &str) -> StorageResult<()> {
        self.storage.set(StorageKeys::DEVICE_ID, device_id)
    }

    /// Retrieve the device ID
    pub fn get_device_id(&self) -> StorageResult<Option<String>> {
        self.storage.get(StorageKeys::DEVICE_ID)
    }

    /// Store the device private key as a base64-encoded global value.
    pub fn set_device_private_key(&self, private_key: &[u8]) -> StorageResult<()> {
        self.storage
            .set(StorageKeys::DEVICE_PRIVATE_KEY, &BASE64.encode(private_key))
    }

    /// Retrieve the device private key.
    ///
    /// The key can be stored as either:
    /// - Raw binary (32 bytes)
    /// - Base64-encoded string
    pub fn get_device_private_key(&self) -> StorageResult<Option<Vec<u8>>> {
        self.get_device_key_bytes(StorageKeys::DEVICE_PRIVATE_KEY)
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
            tracing::warn!(
                "Device key has unexpected format (len={}), returning as-is",
                bytes.len()
            );
            return Ok(Some(bytes));
        }

        Ok(None)
    }

    /// Generate a new device private key (32 bytes random).
    pub fn generate_device_private_key() -> Vec<u8> {
        use rand::RngCore;
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        bytes.to_vec()
    }

    /// Ensure a device private key exists, generating one if needed.
    /// Returns the key (existing or newly generated).
    pub fn ensure_device_private_key(&self) -> StorageResult<Vec<u8>> {
        if let Some(key) = self.get_device_private_key()? {
            return Ok(key);
        }

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

    pub fn has_api_key(&self) -> StorageResult<bool> {
        self.storage.has(StorageKeys::API_KEY)
    }

    pub fn delete_api_key(&self) -> StorageResult<bool> {
        self.storage.delete(StorageKeys::API_KEY)
    }

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
        let base64url = BASE64
            .encode(bytes)
            .replace('+', "-")
            .replace('/', "_")
            .replace('=', "");
        format!("sess_{}", base64url)
    }

    /// Parse session secret to get raw key bytes
    pub fn parse_session_secret(secret: &str) -> StorageResult<Vec<u8>> {
        if !secret.starts_with("sess_") {
            return Err(crate::StorageError::Encoding(
                "Invalid session secret format".to_string(),
            ));
        }
        let base64url = &secret[5..];
        let base64 = base64url.replace('-', "+").replace('_', "/");
        // Add padding
        let padded = match base64.len() % 4 {
            2 => format!("{}==", base64),
            3 => format!("{}=", base64),
            _ => base64,
        };
        BASE64
            .decode(&padded)
            .map_err(|e| crate::StorageError::Encoding(e.to_string()))
    }

    /// Clear all locally managed secrets.
    pub fn clear_all(&self) -> StorageResult<()> {
        let _ = self.storage.delete(StorageKeys::DEVICE_ID);
        let _ = self.storage.delete(StorageKeys::DEVICE_PRIVATE_KEY);
        let _ = self.storage.delete(StorageKeys::API_KEY);
        Ok(())
    }
}
