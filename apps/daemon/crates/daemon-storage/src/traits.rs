//! Storage trait definitions.

use crate::StorageResult;

/// Trait for secure storage backends
pub trait SecureStorage: Send + Sync {
    /// Store a value securely
    fn set(&self, key: &str, value: &str) -> StorageResult<()>;

    /// Retrieve a value
    fn get(&self, key: &str) -> StorageResult<Option<String>>;

    /// Delete a value
    fn delete(&self, key: &str) -> StorageResult<bool>;

    /// Check if a key exists
    fn has(&self, key: &str) -> StorageResult<bool> {
        Ok(self.get(key)?.is_some())
    }

    /// List all keys that start with a given prefix.
    /// Returns an empty vec if not supported or no keys found.
    fn list_keys_with_prefix(&self, _prefix: &str) -> StorageResult<Vec<String>> {
        // Default implementation returns empty - platforms can override
        Ok(Vec::new())
    }

    /// Retrieve a value as raw bytes.
    /// This is useful for binary data that may not be valid UTF-8.
    /// Default implementation converts from string (assumes UTF-8 storage).
    fn get_bytes(&self, key: &str) -> StorageResult<Option<Vec<u8>>> {
        Ok(self.get(key)?.map(|s| s.into_bytes()))
    }
}
