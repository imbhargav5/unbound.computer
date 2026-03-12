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
pub use secrets::SecretsManager;
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
        assert_eq!(
            storage.get("test_key").unwrap(),
            Some("test_value".to_string())
        );

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
        assert_eq!(
            manager.get_device_id().unwrap(),
            Some("device-123".to_string())
        );

        // Test API key
        manager.set_api_key("api-key-456").unwrap();
        assert!(manager.has_api_key().unwrap());
        assert_eq!(
            manager.get_api_key().unwrap(),
            Some("api-key-456".to_string())
        );

        // Test clear all
        manager.clear_all().unwrap();
        assert_eq!(manager.get_device_id().unwrap(), None);
        assert!(!manager.has_api_key().unwrap());
    }

    #[test]
    fn test_secrets_manager_device_private_key() {
        let storage = Box::new(MemoryStorage::new());
        let manager = SecretsManager::new(storage);

        // Set private key (32 bytes)
        let private_key = vec![
            1u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
            24, 25, 26, 27, 28, 29, 30, 31, 32,
        ];
        manager.set_device_private_key(&private_key).unwrap();

        // Get private key
        let retrieved = manager.get_device_private_key().unwrap().unwrap();
        assert_eq!(retrieved, private_key);
    }

    #[test]
    fn test_storage_keys_constants() {
        // Verify all storage keys are defined and non-empty
        assert!(!StorageKeys::DEVICE_ID.is_empty());
        assert!(!StorageKeys::DEVICE_PRIVATE_KEY.is_empty());
        assert!(!StorageKeys::API_KEY.is_empty());

        // Verify keys are unique
        let keys = vec![
            StorageKeys::DEVICE_ID,
            StorageKeys::DEVICE_PRIVATE_KEY,
            StorageKeys::API_KEY,
        ];
        let unique: std::collections::HashSet<_> = keys.iter().collect();
        assert_eq!(unique.len(), keys.len(), "Storage keys must be unique");
    }
}
