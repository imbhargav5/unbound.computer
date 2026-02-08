//! Shared conversation message encryption/decryption helpers.
//!
//! Conversation payloads use ChaCha20-Poly1305 with a 32-byte key and 12-byte nonce.
//! The encrypted bytes and nonce are exported as base64 strings for transport.

use base64::Engine;
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Nonce,
};
use rand::RngCore;
use thiserror::Error;

const BASE64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

/// Conversation nonce size for ChaCha20-Poly1305 (96 bits).
pub const CONVERSATION_NONCE_SIZE: usize = 12;
/// Conversation key size for ChaCha20-Poly1305 (256 bits).
pub const CONVERSATION_KEY_SIZE: usize = 32;

/// Base64-encoded encrypted conversation payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EncryptedConversationPayload {
    /// Base64-encoded ciphertext bytes.
    pub content_encrypted_b64: String,
    /// Base64-encoded nonce bytes.
    pub content_nonce_b64: String,
}

/// Errors returned by conversation crypto helpers.
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ConversationCryptoError {
    #[error("invalid key length: expected {expected}, got {actual}")]
    InvalidKeyLength { expected: usize, actual: usize },
    #[error("invalid nonce length: expected {expected}, got {actual}")]
    InvalidNonceLength { expected: usize, actual: usize },
    #[error("base64 decode failed: {0}")]
    Base64Decode(String),
    #[error("encryption failed: {0}")]
    Encrypt(String),
    #[error("decryption failed: {0}")]
    Decrypt(String),
}

/// Encrypts a conversation message with a fresh random nonce.
pub fn encrypt_conversation_message(
    key: &[u8],
    plaintext: &[u8],
) -> Result<EncryptedConversationPayload, ConversationCryptoError> {
    validate_key_len(key)?;
    let mut nonce = [0u8; CONVERSATION_NONCE_SIZE];
    rand::thread_rng().fill_bytes(&mut nonce);
    encrypt_conversation_message_with_nonce(key, &nonce, plaintext)
}

/// Encrypts a conversation message with a caller-provided nonce.
///
/// This is primarily intended for deterministic tests.
pub fn encrypt_conversation_message_with_nonce(
    key: &[u8],
    nonce: &[u8; CONVERSATION_NONCE_SIZE],
    plaintext: &[u8],
) -> Result<EncryptedConversationPayload, ConversationCryptoError> {
    validate_key_len(key)?;

    let cipher = ChaCha20Poly1305::new_from_slice(key)
        .map_err(|e| ConversationCryptoError::Encrypt(e.to_string()))?;
    let nonce_ref = Nonce::from_slice(nonce);

    let ciphertext = cipher
        .encrypt(nonce_ref, plaintext)
        .map_err(|e| ConversationCryptoError::Encrypt(e.to_string()))?;

    Ok(EncryptedConversationPayload {
        content_encrypted_b64: BASE64.encode(ciphertext),
        content_nonce_b64: BASE64.encode(nonce),
    })
}

/// Decrypts a base64-encoded conversation payload.
pub fn decrypt_conversation_message(
    key: &[u8],
    content_encrypted_b64: &str,
    content_nonce_b64: &str,
) -> Result<Vec<u8>, ConversationCryptoError> {
    validate_key_len(key)?;

    let ciphertext = BASE64
        .decode(content_encrypted_b64)
        .map_err(|e| ConversationCryptoError::Base64Decode(e.to_string()))?;
    let nonce = BASE64
        .decode(content_nonce_b64)
        .map_err(|e| ConversationCryptoError::Base64Decode(e.to_string()))?;

    if nonce.len() != CONVERSATION_NONCE_SIZE {
        return Err(ConversationCryptoError::InvalidNonceLength {
            expected: CONVERSATION_NONCE_SIZE,
            actual: nonce.len(),
        });
    }

    let cipher = ChaCha20Poly1305::new_from_slice(key)
        .map_err(|e| ConversationCryptoError::Decrypt(e.to_string()))?;
    let nonce_ref = Nonce::from_slice(&nonce);

    cipher
        .decrypt(nonce_ref, ciphertext.as_ref())
        .map_err(|e| ConversationCryptoError::Decrypt(e.to_string()))
}

fn validate_key_len(key: &[u8]) -> Result<(), ConversationCryptoError> {
    if key.len() != CONVERSATION_KEY_SIZE {
        return Err(ConversationCryptoError::InvalidKeyLength {
            expected: CONVERSATION_KEY_SIZE,
            actual: key.len(),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypt_decrypt_round_trip() {
        let key = [7u8; CONVERSATION_KEY_SIZE];
        let plaintext = b"hello conversation";

        let encrypted = encrypt_conversation_message(&key, plaintext).unwrap();
        let decrypted = decrypt_conversation_message(
            &key,
            &encrypted.content_encrypted_b64,
            &encrypted.content_nonce_b64,
        )
        .unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn encrypt_with_fixed_nonce_is_deterministic() {
        let key = [1u8; CONVERSATION_KEY_SIZE];
        let nonce = [9u8; CONVERSATION_NONCE_SIZE];
        let plaintext = b"same input";

        let a = encrypt_conversation_message_with_nonce(&key, &nonce, plaintext).unwrap();
        let b = encrypt_conversation_message_with_nonce(&key, &nonce, plaintext).unwrap();

        assert_eq!(a.content_nonce_b64, b.content_nonce_b64);
        assert_eq!(a.content_encrypted_b64, b.content_encrypted_b64);
    }

    #[test]
    fn different_nonce_changes_ciphertext() {
        let key = [5u8; CONVERSATION_KEY_SIZE];
        let plaintext = b"same plaintext";

        let a = encrypt_conversation_message(&key, plaintext).unwrap();
        let b = encrypt_conversation_message(&key, plaintext).unwrap();

        assert_ne!(a.content_nonce_b64, b.content_nonce_b64);
        assert_ne!(a.content_encrypted_b64, b.content_encrypted_b64);
    }

    #[test]
    fn encrypt_rejects_invalid_key_len() {
        let bad_key = [1u8; 16];
        let err = encrypt_conversation_message(&bad_key, b"abc").unwrap_err();
        assert!(matches!(
            err,
            ConversationCryptoError::InvalidKeyLength {
                expected: CONVERSATION_KEY_SIZE,
                actual: 16
            }
        ));
    }

    #[test]
    fn decrypt_rejects_invalid_nonce_len() {
        let key = [7u8; CONVERSATION_KEY_SIZE];
        let nonce_b64 = BASE64.encode([0u8; 8]);
        let cipher_b64 = BASE64.encode([0u8; 32]);

        let err = decrypt_conversation_message(&key, &cipher_b64, &nonce_b64).unwrap_err();
        assert!(matches!(
            err,
            ConversationCryptoError::InvalidNonceLength {
                expected: CONVERSATION_NONCE_SIZE,
                actual: 8
            }
        ));
    }
}

