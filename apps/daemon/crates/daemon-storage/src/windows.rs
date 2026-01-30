//! Windows Credential Vault implementation.

use crate::{SecureStorage, StorageError, StorageResult};
use tracing::debug;
use windows::{
    core::HSTRING,
    Security::Credentials::{PasswordCredential, PasswordVault},
};

/// Credential Vault based secure storage for Windows.
pub struct CredentialStorage {
    resource_name: String,
}

impl CredentialStorage {
    /// Create a new Credential Vault storage instance.
    pub fn new(service_name: &str) -> StorageResult<Self> {
        // Verify we can access the vault
        PasswordVault::new()
            .map_err(|e| StorageError::Platform(format!("Failed to access Credential Vault: {}", e)))?;

        Ok(Self {
            resource_name: service_name.to_string(),
        })
    }

    fn get_vault(&self) -> StorageResult<PasswordVault> {
        PasswordVault::new()
            .map_err(|e| StorageError::Platform(format!("Failed to access Credential Vault: {}", e)))
    }

    fn make_credential(&self, key: &str, value: &str) -> StorageResult<PasswordCredential> {
        let resource = HSTRING::from(&self.resource_name);
        let user_name = HSTRING::from(key);
        let password = HSTRING::from(value);

        PasswordCredential::CreatePasswordCredential(&resource, &user_name, &password)
            .map_err(|e| StorageError::Platform(format!("Failed to create credential: {}", e)))
    }
}

impl SecureStorage for CredentialStorage {
    fn set(&self, key: &str, value: &str) -> StorageResult<()> {
        debug!(resource = %self.resource_name, key = %key, "Setting credential");

        let vault = self.get_vault()?;

        // Delete existing credential first (ignore errors if it doesn't exist)
        let _ = self.delete(key);

        let credential = self.make_credential(key, value)?;
        vault
            .Add(&credential)
            .map_err(|e| StorageError::Platform(format!("Failed to add credential: {}", e)))?;

        Ok(())
    }

    fn get(&self, key: &str) -> StorageResult<Option<String>> {
        debug!(resource = %self.resource_name, key = %key, "Getting credential");

        let vault = self.get_vault()?;
        let resource = HSTRING::from(&self.resource_name);
        let user_name = HSTRING::from(key);

        match vault.Retrieve(&resource, &user_name) {
            Ok(credential) => {
                // Need to call RetrievePassword to populate the Password field
                credential
                    .RetrievePassword()
                    .map_err(|e| StorageError::Platform(format!("Failed to retrieve password: {}", e)))?;

                let password = credential
                    .Password()
                    .map_err(|e| StorageError::Platform(format!("Failed to get password: {}", e)))?;

                Ok(Some(password.to_string()))
            }
            Err(e) => {
                // Check if it's a "not found" error (ERROR_NOT_FOUND = 0x80070490)
                let error_code = e.code().0 as u32;
                if error_code == 0x80070490 {
                    Ok(None)
                } else {
                    Err(StorageError::Platform(format!(
                        "Failed to retrieve credential: {}",
                        e
                    )))
                }
            }
        }
    }

    fn delete(&self, key: &str) -> StorageResult<bool> {
        debug!(resource = %self.resource_name, key = %key, "Deleting credential");

        let vault = self.get_vault()?;
        let resource = HSTRING::from(&self.resource_name);
        let user_name = HSTRING::from(key);

        match vault.Retrieve(&resource, &user_name) {
            Ok(credential) => {
                vault
                    .Remove(&credential)
                    .map_err(|e| StorageError::Platform(format!("Failed to remove credential: {}", e)))?;
                Ok(true)
            }
            Err(e) => {
                let error_code = e.code().0 as u32;
                if error_code == 0x80070490 {
                    Ok(false)
                } else {
                    Err(StorageError::Platform(format!(
                        "Failed to find credential for deletion: {}",
                        e
                    )))
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_RESOURCE: &str = "com.unbound.daemon.test";

    #[test]
    #[ignore] // Requires Windows Credential Vault access
    fn test_credential_operations() {
        let storage = CredentialStorage::new(TEST_RESOURCE).unwrap();

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
