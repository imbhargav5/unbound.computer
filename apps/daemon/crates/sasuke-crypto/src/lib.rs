//! Device identity and crypto coordination for the Unbound daemon.
//!
//! Manages loading device ID/private key from keychain, deriving database
//! encryption keys, and decrypting session secrets from Supabase.

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use thiserror::Error;

/// Errors from device identity and crypto operations.
#[derive(Error, Debug)]
pub enum CryptoError {
    #[error("No device ID available")]
    NoDeviceId,
    #[error("No device private key available")]
    NoDevicePrivateKey,
    #[error("No access token available")]
    NoAccessToken,
    #[error("Failed to get database encryption key: {0}")]
    EncryptionKeyError(String),
    #[error("Failed to decode base64: {0}")]
    Base64Decode(String),
    #[error("Invalid key length: expected {expected}, got {actual}")]
    InvalidKeyLength { expected: usize, actual: usize },
    #[error("Decryption failed: {0}")]
    DecryptionFailed(String),
    #[error("Invalid UTF-8 in decrypted secret")]
    InvalidUtf8,
    #[error("Failed to parse session secret: {0}")]
    SecretParseFailed(String),
    #[error("Storage error: {0}")]
    Storage(String),
}

/// Cached device identity material.
#[derive(Debug, Clone)]
pub struct DeviceIdentity {
    pub device_id: Option<String>,
    pub device_private_key: Option<[u8; 32]>,
    pub db_encryption_key: Option<[u8; 32]>,
}

impl DeviceIdentity {
    /// Create an empty identity (no device registered yet).
    pub fn empty() -> Self {
        Self {
            device_id: None,
            device_private_key: None,
            db_encryption_key: None,
        }
    }

    /// Create an identity with all fields populated.
    pub fn new(
        device_id: String,
        device_private_key: [u8; 32],
        db_encryption_key: [u8; 32],
    ) -> Self {
        Self {
            device_id: Some(device_id),
            device_private_key: Some(device_private_key),
            db_encryption_key: Some(db_encryption_key),
        }
    }

    /// Check if the device has been fully registered.
    pub fn is_registered(&self) -> bool {
        self.device_id.is_some() && self.device_private_key.is_some()
    }

    /// Check if database encryption is available.
    pub fn has_encryption_key(&self) -> bool {
        self.db_encryption_key.is_some()
    }
}

impl Default for DeviceIdentity {
    fn default() -> Self {
        Self::empty()
    }
}

/// Decode a base64-encoded 32-byte key.
pub fn decode_key_base64(encoded: &str) -> Result<[u8; 32], CryptoError> {
    let bytes = BASE64
        .decode(encoded)
        .map_err(|e| CryptoError::Base64Decode(e.to_string()))?;
    if bytes.len() != 32 {
        return Err(CryptoError::InvalidKeyLength {
            expected: 32,
            actual: bytes.len(),
        });
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

/// Decode a base64-encoded byte vector (arbitrary length).
pub fn decode_bytes_base64(encoded: &str) -> Result<Vec<u8>, CryptoError> {
    BASE64
        .decode(encoded)
        .map_err(|e| CryptoError::Base64Decode(e.to_string()))
}

/// Encode bytes to base64.
pub fn encode_base64(bytes: &[u8]) -> String {
    BASE64.encode(bytes)
}

/// A remote session secret record from Supabase.
#[derive(Debug, Clone)]
pub struct RemoteSecretRecord {
    pub session_id: String,
    pub ephemeral_public_key: String,
    pub encrypted_secret: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    // =========================================================================
    // DeviceIdentity tests
    // =========================================================================

    #[test]
    fn identity_empty_is_not_registered() {
        let id = DeviceIdentity::empty();
        assert!(!id.is_registered());
        assert!(!id.has_encryption_key());
        assert!(id.device_id.is_none());
        assert!(id.device_private_key.is_none());
        assert!(id.db_encryption_key.is_none());
    }

    #[test]
    fn identity_default_is_empty() {
        let id = DeviceIdentity::default();
        assert!(!id.is_registered());
    }

    #[test]
    fn identity_new_is_registered() {
        let id = DeviceIdentity::new(
            "device-123".to_string(),
            [1u8; 32],
            [2u8; 32],
        );
        assert!(id.is_registered());
        assert!(id.has_encryption_key());
        assert_eq!(id.device_id.as_deref(), Some("device-123"));
    }

    #[test]
    fn identity_partial_not_registered() {
        let mut id = DeviceIdentity::empty();
        id.device_id = Some("device-abc".to_string());
        // Has device_id but no private key
        assert!(!id.is_registered());
    }

    #[test]
    fn identity_no_encryption_key() {
        let mut id = DeviceIdentity::empty();
        id.device_id = Some("d1".to_string());
        id.device_private_key = Some([0u8; 32]);
        assert!(id.is_registered());
        assert!(!id.has_encryption_key());
    }

    #[test]
    fn identity_clone() {
        let id = DeviceIdentity::new("d1".to_string(), [1u8; 32], [2u8; 32]);
        let cloned = id.clone();
        assert_eq!(cloned.device_id, id.device_id);
        assert_eq!(cloned.device_private_key, id.device_private_key);
        assert_eq!(cloned.db_encryption_key, id.db_encryption_key);
    }

    // =========================================================================
    // Base64 encoding/decoding tests
    // =========================================================================

    #[test]
    fn decode_key_base64_valid() {
        let key = [42u8; 32];
        let encoded = BASE64.encode(key);
        let decoded = decode_key_base64(&encoded).unwrap();
        assert_eq!(decoded, key);
    }

    #[test]
    fn decode_key_base64_wrong_length() {
        let short = BASE64.encode([1u8; 16]);
        let result = decode_key_base64(&short);
        assert!(matches!(
            result,
            Err(CryptoError::InvalidKeyLength {
                expected: 32,
                actual: 16
            })
        ));
    }

    #[test]
    fn decode_key_base64_too_long() {
        let long = BASE64.encode([1u8; 64]);
        let result = decode_key_base64(&long);
        assert!(matches!(
            result,
            Err(CryptoError::InvalidKeyLength {
                expected: 32,
                actual: 64
            })
        ));
    }

    #[test]
    fn decode_key_base64_invalid_base64() {
        let result = decode_key_base64("not valid base64!!!");
        assert!(matches!(result, Err(CryptoError::Base64Decode(_))));
    }

    #[test]
    fn decode_key_base64_empty_string() {
        let result = decode_key_base64("");
        assert!(matches!(
            result,
            Err(CryptoError::InvalidKeyLength {
                expected: 32,
                actual: 0
            })
        ));
    }

    #[test]
    fn decode_bytes_base64_valid() {
        let data = vec![1, 2, 3, 4, 5];
        let encoded = BASE64.encode(&data);
        let decoded = decode_bytes_base64(&encoded).unwrap();
        assert_eq!(decoded, data);
    }

    #[test]
    fn decode_bytes_base64_empty() {
        let decoded = decode_bytes_base64("").unwrap();
        assert!(decoded.is_empty());
    }

    #[test]
    fn decode_bytes_base64_invalid() {
        let result = decode_bytes_base64("!!!invalid!!!");
        assert!(matches!(result, Err(CryptoError::Base64Decode(_))));
    }

    #[test]
    fn encode_base64_roundtrip() {
        let data = vec![0, 127, 255, 42, 17];
        let encoded = encode_base64(&data);
        let decoded = decode_bytes_base64(&encoded).unwrap();
        assert_eq!(decoded, data);
    }

    #[test]
    fn encode_base64_empty() {
        let encoded = encode_base64(&[]);
        assert_eq!(encoded, "");
    }

    #[test]
    fn encode_base64_key_roundtrip() {
        let key = [99u8; 32];
        let encoded = encode_base64(&key);
        let decoded = decode_key_base64(&encoded).unwrap();
        assert_eq!(decoded, key);
    }

    // =========================================================================
    // Error display tests
    // =========================================================================

    #[test]
    fn error_no_device_id_display() {
        let e = CryptoError::NoDeviceId;
        assert_eq!(e.to_string(), "No device ID available");
    }

    #[test]
    fn error_no_private_key_display() {
        let e = CryptoError::NoDevicePrivateKey;
        assert_eq!(e.to_string(), "No device private key available");
    }

    #[test]
    fn error_invalid_key_length_display() {
        let e = CryptoError::InvalidKeyLength {
            expected: 32,
            actual: 16,
        };
        let msg = e.to_string();
        assert!(msg.contains("32"));
        assert!(msg.contains("16"));
    }

    #[test]
    fn error_base64_decode_display() {
        let e = CryptoError::Base64Decode("bad input".to_string());
        assert!(e.to_string().contains("bad input"));
    }

    #[test]
    fn error_decryption_failed_display() {
        let e = CryptoError::DecryptionFailed("MAC mismatch".to_string());
        assert!(e.to_string().contains("MAC mismatch"));
    }

    #[test]
    fn error_storage_display() {
        let e = CryptoError::Storage("keychain locked".to_string());
        assert!(e.to_string().contains("keychain locked"));
    }

    // =========================================================================
    // RemoteSecretRecord tests
    // =========================================================================

    #[test]
    fn remote_secret_record_clone() {
        let record = RemoteSecretRecord {
            session_id: "sess-1".to_string(),
            ephemeral_public_key: "key123".to_string(),
            encrypted_secret: "enc456".to_string(),
        };
        let cloned = record.clone();
        assert_eq!(cloned.session_id, "sess-1");
        assert_eq!(cloned.ephemeral_public_key, "key123");
        assert_eq!(cloned.encrypted_secret, "enc456");
    }
}
