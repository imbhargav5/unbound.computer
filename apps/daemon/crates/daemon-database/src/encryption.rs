//! ChaCha20-Poly1305 encryption for message content.

use crate::{DatabaseError, DatabaseResult};
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Nonce,
};
use rand::RngCore;

/// Nonce size for ChaCha20-Poly1305 (96 bits = 12 bytes).
pub const NONCE_SIZE: usize = 12;

/// Key size for ChaCha20-Poly1305 (256 bits = 32 bytes).
pub const KEY_SIZE: usize = 32;

/// Generate a random nonce for encryption.
pub fn generate_nonce() -> [u8; NONCE_SIZE] {
    let mut nonce = [0u8; NONCE_SIZE];
    rand::thread_rng().fill_bytes(&mut nonce);
    nonce
}

/// Generate a random encryption key.
pub fn generate_key() -> [u8; KEY_SIZE] {
    let mut key = [0u8; KEY_SIZE];
    rand::thread_rng().fill_bytes(&mut key);
    key
}

/// Encrypt content using ChaCha20-Poly1305.
///
/// # Arguments
/// * `key` - 32-byte encryption key
/// * `nonce` - 12-byte nonce (must be unique for each encryption with same key)
/// * `plaintext` - Data to encrypt
///
/// # Returns
/// Ciphertext with authentication tag appended
pub fn encrypt_content(key: &[u8], nonce: &[u8], plaintext: &[u8]) -> DatabaseResult<Vec<u8>> {
    if key.len() != KEY_SIZE {
        return Err(DatabaseError::Encryption(format!(
            "Invalid key size: expected {}, got {}",
            KEY_SIZE,
            key.len()
        )));
    }

    if nonce.len() != NONCE_SIZE {
        return Err(DatabaseError::Encryption(format!(
            "Invalid nonce size: expected {}, got {}",
            NONCE_SIZE,
            nonce.len()
        )));
    }

    let cipher = ChaCha20Poly1305::new_from_slice(key)
        .map_err(|e| DatabaseError::Encryption(e.to_string()))?;

    let nonce = Nonce::from_slice(nonce);

    cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| DatabaseError::Encryption(e.to_string()))
}

/// Decrypt content using ChaCha20-Poly1305.
///
/// # Arguments
/// * `key` - 32-byte encryption key
/// * `nonce` - 12-byte nonce used during encryption
/// * `ciphertext` - Encrypted data with authentication tag
///
/// # Returns
/// Decrypted plaintext
pub fn decrypt_content(key: &[u8], nonce: &[u8], ciphertext: &[u8]) -> DatabaseResult<Vec<u8>> {
    if key.len() != KEY_SIZE {
        return Err(DatabaseError::Encryption(format!(
            "Invalid key size: expected {}, got {}",
            KEY_SIZE,
            key.len()
        )));
    }

    if nonce.len() != NONCE_SIZE {
        return Err(DatabaseError::Encryption(format!(
            "Invalid nonce size: expected {}, got {}",
            NONCE_SIZE,
            nonce.len()
        )));
    }

    let cipher = ChaCha20Poly1305::new_from_slice(key)
        .map_err(|e| DatabaseError::Encryption(e.to_string()))?;

    let nonce = Nonce::from_slice(nonce);

    cipher
        .decrypt(nonce, ciphertext)
        .map_err(|e| DatabaseError::Encryption(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let key = generate_key();
        let nonce = generate_nonce();
        let plaintext = b"Hello, World! This is a test message.";

        let ciphertext = encrypt_content(&key, &nonce, plaintext).unwrap();
        assert_ne!(ciphertext, plaintext);

        let decrypted = decrypt_content(&key, &nonce, &ciphertext).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_wrong_key_fails() {
        let key1 = generate_key();
        let key2 = generate_key();
        let nonce = generate_nonce();
        let plaintext = b"Secret message";

        let ciphertext = encrypt_content(&key1, &nonce, plaintext).unwrap();

        // Decrypting with wrong key should fail
        let result = decrypt_content(&key2, &nonce, &ciphertext);
        assert!(result.is_err());
    }

    #[test]
    fn test_wrong_nonce_fails() {
        let key = generate_key();
        let nonce1 = generate_nonce();
        let nonce2 = generate_nonce();
        let plaintext = b"Secret message";

        let ciphertext = encrypt_content(&key, &nonce1, plaintext).unwrap();

        // Decrypting with wrong nonce should fail
        let result = decrypt_content(&key, &nonce2, &ciphertext);
        assert!(result.is_err());
    }

    #[test]
    fn test_invalid_key_size() {
        let short_key = [0u8; 16]; // Too short
        let nonce = generate_nonce();
        let plaintext = b"Test";

        let result = encrypt_content(&short_key, &nonce, plaintext);
        assert!(result.is_err());
    }

    #[test]
    fn test_invalid_nonce_size() {
        let key = generate_key();
        let short_nonce = [0u8; 8]; // Too short
        let plaintext = b"Test";

        let result = encrypt_content(&key, &short_nonce, plaintext);
        assert!(result.is_err());
    }
}
