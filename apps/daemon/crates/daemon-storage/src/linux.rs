//! Linux Secret Service implementation.

use crate::{SecureStorage, StorageError, StorageResult};
use secret_service::{blocking::SecretService, EncryptionType};
use std::collections::HashMap;
use tracing::debug;

/// Secret Service based secure storage for Linux.
pub struct SecretServiceStorage {
    service_name: String,
}

impl SecretServiceStorage {
    /// Create a new Secret Service storage instance.
    pub fn new(service_name: &str) -> StorageResult<Self> {
        // Verify we can connect to Secret Service
        SecretService::connect(EncryptionType::Dh)
            .map_err(|e| StorageError::Platform(format!("Failed to connect to Secret Service: {}", e)))?;

        Ok(Self {
            service_name: service_name.to_string(),
        })
    }

    fn with_collection<F, T>(&self, f: F) -> StorageResult<T>
    where
        F: FnOnce(&secret_service::blocking::Collection) -> StorageResult<T>,
    {
        let ss = SecretService::connect(EncryptionType::Dh)
            .map_err(|e| StorageError::Platform(e.to_string()))?;

        let collection = ss
            .get_default_collection()
            .map_err(|e| StorageError::Platform(e.to_string()))?;

        // Unlock the collection if needed
        if collection.is_locked().unwrap_or(false) {
            collection
                .unlock()
                .map_err(|e| StorageError::Platform(format!("Failed to unlock collection: {}", e)))?;
        }

        f(&collection)
    }

    fn build_attributes<'a>(&'a self, key: &'a str) -> HashMap<&'a str, &'a str> {
        let mut attrs = HashMap::new();
        attrs.insert("service", self.service_name.as_str());
        attrs.insert("key", key);
        attrs
    }
}

impl SecureStorage for SecretServiceStorage {
    fn set(&self, key: &str, value: &str) -> StorageResult<()> {
        debug!(service = %self.service_name, key = %key, "Setting secret");

        // Delete existing item first
        let _ = self.delete(key);

        self.with_collection(|collection| {
            let attrs = self.build_attributes(key);
            let label = format!("{}/{}", self.service_name, key);

            collection
                .create_item(
                    &label,
                    attrs,
                    value.as_bytes(),
                    true, // replace
                    "text/plain",
                )
                .map_err(|e| StorageError::Platform(e.to_string()))?;

            Ok(())
        })
    }

    fn get(&self, key: &str) -> StorageResult<Option<String>> {
        debug!(service = %self.service_name, key = %key, "Getting secret");

        self.with_collection(|collection| {
            let attrs = self.build_attributes(key);

            let items = collection
                .search_items(attrs)
                .map_err(|e| StorageError::Platform(e.to_string()))?;

            if items.is_empty() {
                return Ok(None);
            }

            let secret = items[0]
                .get_secret()
                .map_err(|e| StorageError::Platform(e.to_string()))?;

            let value = String::from_utf8(secret)
                .map_err(|e| StorageError::Encoding(e.to_string()))?;

            Ok(Some(value))
        })
    }

    fn delete(&self, key: &str) -> StorageResult<bool> {
        debug!(service = %self.service_name, key = %key, "Deleting secret");

        self.with_collection(|collection| {
            let attrs = self.build_attributes(key);

            let items = collection
                .search_items(attrs)
                .map_err(|e| StorageError::Platform(e.to_string()))?;

            if items.is_empty() {
                return Ok(false);
            }

            items[0]
                .delete()
                .map_err(|e| StorageError::Platform(e.to_string()))?;

            Ok(true)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_SERVICE: &str = "com.unbound.daemon.test";

    #[test]
    #[ignore] // Requires Linux Secret Service (D-Bus)
    fn test_secret_service_operations() {
        let storage = SecretServiceStorage::new(TEST_SERVICE).unwrap();

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
