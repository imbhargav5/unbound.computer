//! Secure storage abstraction for the Unbound daemon.
//!
//! This crate provides platform-specific secure storage implementations:
//! - **macOS**: Keychain Access via `security-framework`
//! - **Linux**: Secret Service (GNOME Keyring / KWallet) via `secret-service`
//! - **Windows**: Credential Vault via `windows` crate

mod keys;
mod secrets;
mod traits;

#[cfg(target_os = "macos")]
mod macos;

#[cfg(target_os = "linux")]
mod linux;

#[cfg(target_os = "windows")]
mod windows;

pub use keys::StorageKeys;
pub use secrets::{SecretsManager, SupabaseSessionMeta, TrustRole, TrustedDevice};
pub use traits::SecureStorage;

use thiserror::Error;

/// Service name used for all storage operations.
/// Must match the macOS app's service name to share keychain entries.
pub const SERVICE_NAME: &str = "com.unbound.macos";

/// Error type for storage operations.
#[derive(Error, Debug)]
pub enum StorageError {
    /// Platform-specific storage error
    #[error("Platform storage error: {0}")]
    Platform(String),

    /// Key not found
    #[error("Key not found: {0}")]
    NotFound(String),

    /// Encoding/decoding error
    #[error("Encoding error: {0}")]
    Encoding(String),

    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

/// Result type for storage operations.
pub type StorageResult<T> = Result<T, StorageError>;

/// Create the default platform-specific storage implementation.
pub fn create_storage() -> StorageResult<Box<dyn SecureStorage>> {
    #[cfg(target_os = "macos")]
    {
        let storage = macos::KeychainStorage::new(SERVICE_NAME)?;
        Ok(Box::new(storage))
    }

    #[cfg(target_os = "linux")]
    {
        let storage = linux::SecretServiceStorage::new(SERVICE_NAME)?;
        Ok(Box::new(storage))
    }

    #[cfg(target_os = "windows")]
    {
        let storage = windows::CredentialStorage::new(SERVICE_NAME)?;
        Ok(Box::new(storage))
    }

    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        Err(StorageError::Platform(
            "No secure storage implementation available for this platform".to_string(),
        ))
    }
}

/// Create a SecretsManager with the default platform storage.
pub fn create_secrets_manager() -> StorageResult<SecretsManager> {
    let storage = create_storage()?;
    Ok(SecretsManager::new(storage))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// In-memory storage for testing
    pub struct MemoryStorage {
        data: std::sync::Mutex<std::collections::HashMap<String, String>>,
    }

    impl MemoryStorage {
        pub fn new() -> Self {
            Self {
                data: std::sync::Mutex::new(std::collections::HashMap::new()),
            }
        }
    }

    impl SecureStorage for MemoryStorage {
        fn set(&self, key: &str, value: &str) -> StorageResult<()> {
            let mut data = self.data.lock().unwrap();
            data.insert(key.to_string(), value.to_string());
            Ok(())
        }

        fn get(&self, key: &str) -> StorageResult<Option<String>> {
            let data = self.data.lock().unwrap();
            Ok(data.get(key).cloned())
        }

        fn delete(&self, key: &str) -> StorageResult<bool> {
            let mut data = self.data.lock().unwrap();
            Ok(data.remove(key).is_some())
        }
    }

    #[test]
    fn test_memory_storage() {
        let storage = MemoryStorage::new();

        // Test set and get
        storage.set("test_key", "test_value").unwrap();
        assert_eq!(storage.get("test_key").unwrap(), Some("test_value".to_string()));

        // Test has
        assert!(storage.has("test_key").unwrap());
        assert!(!storage.has("nonexistent").unwrap());

        // Test delete
        assert!(storage.delete("test_key").unwrap());
        assert!(!storage.delete("test_key").unwrap());
        assert_eq!(storage.get("test_key").unwrap(), None);
    }

    #[test]
    fn test_secrets_manager() {
        let storage = Box::new(MemoryStorage::new());
        let manager = SecretsManager::new(storage);

        // Test device ID
        manager.set_device_id("device-123").unwrap();
        assert_eq!(manager.get_device_id().unwrap(), Some("device-123".to_string()));

        // Test API key
        manager.set_api_key("api-key-456").unwrap();
        assert!(manager.has_api_key().unwrap());
        assert_eq!(manager.get_api_key().unwrap(), Some("api-key-456".to_string()));

        // Test clear all
        manager.clear_all().unwrap();
        assert_eq!(manager.get_device_id().unwrap(), None);
        assert!(!manager.has_api_key().unwrap());
    }

    #[test]
    fn test_secrets_manager_supabase_session() {
        let storage = Box::new(MemoryStorage::new());
        let manager = SecretsManager::new(storage);

        // Initially no session
        assert!(!manager.has_supabase_session().unwrap());

        // Set session using convenience method
        let future_time = (chrono::Utc::now() + chrono::Duration::hours(1)).to_rfc3339();
        manager.set_supabase_session(
            "access-token",
            "refresh-token",
            "user-123",
            Some("test@example.com"),
            &future_time,
        ).unwrap();

        // Session should exist
        assert!(manager.has_supabase_session().unwrap());

        // Verify individual tokens
        assert_eq!(manager.get_supabase_access_token().unwrap(), Some("access-token".to_string()));
        assert_eq!(manager.get_supabase_refresh_token().unwrap(), Some("refresh-token".to_string()));

        // Verify metadata
        let meta = manager.get_supabase_session_meta().unwrap().unwrap();
        assert_eq!(meta.user_id, "user-123");
        assert_eq!(meta.project_ref, "default");

        // Clear session
        manager.clear_supabase_session().unwrap();
        assert!(!manager.has_supabase_session().unwrap());
        assert!(manager.get_supabase_access_token().unwrap().is_none());
    }

    #[test]
    fn test_secrets_manager_session_expired() {
        let storage = Box::new(MemoryStorage::new());
        let manager = SecretsManager::new(storage);

        // Set expired session (past time)
        let past_time = (chrono::Utc::now() - chrono::Duration::hours(1)).to_rfc3339();
        manager.set_supabase_session(
            "access-token",
            "refresh-token",
            "user-123",
            Some("test@example.com"),
            &past_time,
        ).unwrap();

        // Session exists but is expired
        assert!(manager.has_supabase_session().unwrap());
        assert!(manager.is_supabase_session_expired().unwrap());

        // Set valid session (future time)
        let future_time = (chrono::Utc::now() + chrono::Duration::hours(1)).to_rfc3339();
        manager.set_supabase_session(
            "access-token-2",
            "refresh-token-2",
            "user-456",
            Some("test2@example.com"),
            &future_time,
        ).unwrap();

        // Session should not be expired
        assert!(!manager.is_supabase_session_expired().unwrap());
    }

    #[test]
    fn test_secrets_manager_trusted_devices() {
        let storage = Box::new(MemoryStorage::new());
        let manager = SecretsManager::new(storage);

        // Initially no trusted devices
        let devices = manager.get_trusted_devices().unwrap();
        assert!(devices.is_empty());

        // Add a trusted device
        let device1 = TrustedDevice {
            device_id: "device-1".to_string(),
            name: "My MacBook".to_string(),
            public_key: "pubkey-1".to_string(),
            role: TrustRole::TrustRoot,
            trusted_at: chrono::Utc::now().to_rfc3339(),
            expires_at: None,
        };
        manager.add_trusted_device(device1.clone()).unwrap();

        // Verify device was added
        let devices = manager.get_trusted_devices().unwrap();
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].device_id, "device-1");
        assert_eq!(devices[0].name, "My MacBook");
        assert_eq!(devices[0].role, TrustRole::TrustRoot);

        // Add another device
        let device2 = TrustedDevice {
            device_id: "device-2".to_string(),
            name: "My iPhone".to_string(),
            public_key: "pubkey-2".to_string(),
            role: TrustRole::TrustedExecutor,
            trusted_at: chrono::Utc::now().to_rfc3339(),
            expires_at: Some((chrono::Utc::now() + chrono::Duration::days(30)).to_rfc3339()),
        };
        manager.add_trusted_device(device2).unwrap();

        let devices = manager.get_trusted_devices().unwrap();
        assert_eq!(devices.len(), 2);

        // Remove first device
        assert!(manager.remove_trusted_device("device-1").unwrap());
        let devices = manager.get_trusted_devices().unwrap();
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].device_id, "device-2");

        // Removing non-existent device returns false
        assert!(!manager.remove_trusted_device("nonexistent").unwrap());
    }

    #[test]
    fn test_secrets_manager_device_private_key() {
        let storage = Box::new(MemoryStorage::new());
        let manager = SecretsManager::new(storage);

        // Set private key (32 bytes)
        let private_key = vec![1u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
                               17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32];
        manager.set_device_private_key(&private_key).unwrap();

        // Get private key
        let retrieved = manager.get_device_private_key().unwrap().unwrap();
        assert_eq!(retrieved, private_key);
    }

    #[test]
    fn test_storage_keys_constants() {
        // Verify all storage keys are defined and non-empty
        assert!(!StorageKeys::MASTER_KEY.is_empty());
        assert!(!StorageKeys::DEVICE_ID.is_empty());
        assert!(!StorageKeys::DEVICE_PRIVATE_KEY.is_empty());
        assert!(!StorageKeys::API_KEY.is_empty());
        assert!(!StorageKeys::TRUSTED_DEVICES.is_empty());
        assert!(!StorageKeys::SUPABASE_ACCESS_TOKEN.is_empty());
        assert!(!StorageKeys::SUPABASE_REFRESH_TOKEN.is_empty());
        assert!(!StorageKeys::SUPABASE_SESSION_META.is_empty());

        // Verify keys are unique
        let keys = vec![
            StorageKeys::MASTER_KEY,
            StorageKeys::DEVICE_ID,
            StorageKeys::DEVICE_PRIVATE_KEY,
            StorageKeys::API_KEY,
            StorageKeys::TRUSTED_DEVICES,
            StorageKeys::SUPABASE_ACCESS_TOKEN,
            StorageKeys::SUPABASE_REFRESH_TOKEN,
            StorageKeys::SUPABASE_SESSION_META,
        ];
        let unique: std::collections::HashSet<_> = keys.iter().collect();
        assert_eq!(unique.len(), keys.len(), "Storage keys must be unique");
    }
}
