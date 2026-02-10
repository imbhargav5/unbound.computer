//! macOS Keychain implementation.

use crate::{SecureStorage, StorageError, StorageResult};
use security_framework::item::{ItemClass, ItemSearchOptions, Limit, SearchResult};
use security_framework::passwords::{delete_generic_password, set_generic_password};
use tracing::debug;

/// Keychain-based secure storage for macOS.
pub struct KeychainStorage {
    service_name: String,
}

impl KeychainStorage {
    /// Create a new Keychain storage instance.
    pub fn new(service_name: &str) -> StorageResult<Self> {
        Ok(Self {
            service_name: service_name.to_string(),
        })
    }

    /// Search keychain returning raw bytes.
    fn search_keychain_bytes(&self, key: &str) -> StorageResult<Option<Vec<u8>>> {
        let mut search = ItemSearchOptions::new();
        search
            .class(ItemClass::generic_password())
            .service(&self.service_name)
            .account(key)
            .limit(Limit::Max(1))
            .load_data(true);

        match search.search() {
            Ok(results) => {
                if results.is_empty() {
                    return Ok(None);
                }

                if let Some(SearchResult::Data(data)) = results.into_iter().next() {
                    return Ok(Some(data));
                }

                Ok(None)
            }
            Err(e) => {
                let error_str = e.to_string().to_lowercase();
                // Handle "item not found" errors - various forms the error can take
                if error_str.contains("not found")
                    || error_str.contains("could not be found")
                    || error_str.contains("-25300")
                    || error_str.contains("errSecItemNotFound")
                {
                    Ok(None)
                } else {
                    Err(StorageError::Platform(format!(
                        "Failed to get keychain item: {}",
                        e
                    )))
                }
            }
        }
    }

    /// Search keychain returning string (UTF-8).
    fn search_keychain_string(&self, key: &str) -> StorageResult<Option<String>> {
        match self.search_keychain_bytes(key)? {
            Some(data) => {
                let value =
                    String::from_utf8(data).map_err(|e| StorageError::Encoding(e.to_string()))?;
                Ok(Some(value))
            }
            None => Ok(None),
        }
    }
}

impl SecureStorage for KeychainStorage {
    fn set(&self, key: &str, value: &str) -> StorageResult<()> {
        debug!(service = %self.service_name, key = %key, "Setting keychain item");

        // Delete existing item first (ignore errors if it doesn't exist)
        let _ = delete_generic_password(&self.service_name, key);

        // Note: set_generic_password doesn't support access groups directly.
        // For items created by the macOS app with access group, we can read them
        // but creating new items would need lower-level APIs.
        // For now, we use the standard API which works for daemon-created items.
        set_generic_password(&self.service_name, key, value.as_bytes())
            .map_err(|e| StorageError::Platform(format!("Failed to set keychain item: {}", e)))?;

        Ok(())
    }

    fn get(&self, key: &str) -> StorageResult<Option<String>> {
        debug!(service = %self.service_name, key = %key, "Getting keychain item");
        self.search_keychain_string(key)
    }

    fn get_bytes(&self, key: &str) -> StorageResult<Option<Vec<u8>>> {
        debug!(service = %self.service_name, key = %key, "Getting keychain item as bytes");
        self.search_keychain_bytes(key)
    }

    fn delete(&self, key: &str) -> StorageResult<bool> {
        debug!(service = %self.service_name, key = %key, "Deleting keychain item");

        match delete_generic_password(&self.service_name, key) {
            Ok(()) => Ok(true),
            Err(e) => {
                let error_str = e.to_string();
                if error_str.contains("not found") || error_str.contains("-25300") {
                    Ok(false)
                } else {
                    Err(StorageError::Platform(format!(
                        "Failed to delete keychain item: {}",
                        e
                    )))
                }
            }
        }
    }

    fn list_keys_with_prefix(&self, prefix: &str) -> StorageResult<Vec<String>> {
        // Listing keychain items by prefix is not supported without dump-keychain
        // which requires user permission. Callers should use specific key names.
        debug!(service = %self.service_name, prefix = %prefix, "Keychain prefix listing not supported");
        Ok(Vec::new())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Note: These tests require access to the macOS Keychain
    // and should be run with appropriate permissions.
    // They use a test-specific service name to avoid conflicts.

    const TEST_SERVICE: &str = "com.unbound.daemon.test";

    #[test]
    #[ignore] // Requires macOS Keychain access
    fn test_keychain_operations() {
        let storage = KeychainStorage::new(TEST_SERVICE).unwrap();

        // Clean up from previous test runs
        let _ = storage.delete("test_key");

        // Test set and get
        storage.set("test_key", "test_value").unwrap();
        assert_eq!(
            storage.get("test_key").unwrap(),
            Some("test_value".to_string())
        );

        // Test overwrite
        storage.set("test_key", "new_value").unwrap();
        assert_eq!(
            storage.get("test_key").unwrap(),
            Some("new_value".to_string())
        );

        // Test has
        assert!(storage.has("test_key").unwrap());
        assert!(!storage.has("nonexistent").unwrap());

        // Test delete
        assert!(storage.delete("test_key").unwrap());
        assert!(!storage.delete("test_key").unwrap());
        assert_eq!(storage.get("test_key").unwrap(), None);
    }
}
