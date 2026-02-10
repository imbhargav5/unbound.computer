//! Hybrid encryption using X25519 ECDH + HKDF-SHA256 + ChaCha20-Poly1305.
//!
//! This module provides device-to-device encryption for session secrets.
//! The scheme uses:
//! - X25519 for ephemeral key exchange (ECDH)
//! - HKDF-SHA256 for key derivation
//! - ChaCha20-Poly1305 for authenticated encryption
//!
//! HKDF Parameters (must match macOS/iOS implementations):
//! - Hash: SHA-256
//! - Salt: session_id string bytes
//! - Info: b"unbound-session-secret-v1"
//! - Output: 32 bytes

use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Key, Nonce,
};
use hkdf::Hkdf;
use rand::RngCore;
use sha2::Sha256;
use x25519_dalek::{EphemeralSecret, PublicKey, StaticSecret};

use crate::error::{CoreError, CoreResult};

/// HKDF info string for session secret encryption (must match iOS/macOS).
const HKDF_INFO: &[u8] = b"unbound-session-secret-v1";

/// Nonce size for ChaCha20-Poly1305 (12 bytes / 96 bits).
const NONCE_SIZE: usize = 12;

/// Key size for X25519 public/private keys and ChaCha20 symmetric key (32 bytes).
const KEY_SIZE: usize = 32;

/// Generates a random 12-byte nonce for ChaCha20-Poly1305.
fn generate_random_nonce() -> [u8; NONCE_SIZE] {
    let mut nonce = [0u8; NONCE_SIZE];
    rand::thread_rng().fill_bytes(&mut nonce);
    nonce
}

/// Encrypt data for a specific device using hybrid encryption.
///
/// This function:
/// 1. Generates an ephemeral X25519 keypair
/// 2. Computes a shared secret via ECDH with the recipient's public key
/// 3. Derives a symmetric key using HKDF-SHA256
/// 4. Encrypts the plaintext with ChaCha20-Poly1305
///
/// # Arguments
/// * `plaintext` - The data to encrypt (typically a session secret)
/// * `recipient_public_key` - The recipient device's X25519 public key (32 bytes)
/// * `session_id` - The session ID string, used as HKDF salt for domain separation
///
/// # Returns
/// A tuple of:
/// * `[u8; 32]` - The ephemeral public key (to be sent with the ciphertext)
/// * `Vec<u8>` - The encrypted data: nonce(12) || ciphertext || tag(16)
pub fn encrypt_for_device(
    plaintext: &[u8],
    recipient_public_key: &[u8; KEY_SIZE],
    session_id: &str,
) -> CoreResult<([u8; KEY_SIZE], Vec<u8>)> {
    // 1. Generate ephemeral X25519 keypair
    let ephemeral_secret = EphemeralSecret::random_from_rng(rand::thread_rng());
    let ephemeral_public = PublicKey::from(&ephemeral_secret);

    // 2. Compute shared secret via ECDH
    let recipient_public = PublicKey::from(*recipient_public_key);
    let shared_secret = ephemeral_secret.diffie_hellman(&recipient_public);

    // 3. Derive symmetric key with HKDF-SHA256
    let hkdf = Hkdf::<Sha256>::new(
        Some(session_id.as_bytes()), // Salt = session UUID string
        shared_secret.as_bytes(),
    );
    let mut symmetric_key = [0u8; KEY_SIZE];
    hkdf.expand(HKDF_INFO, &mut symmetric_key)
        .map_err(|e| CoreError::Crypto(format!("HKDF expand failed: {e}")))?;

    // 4. Encrypt with ChaCha20-Poly1305
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&symmetric_key));
    let nonce = generate_random_nonce();
    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce), plaintext)
        .map_err(|e| CoreError::Crypto(format!("Encryption failed: {e}")))?;

    // 5. Return ephemeral public key + combined (nonce || ciphertext || tag)
    let mut combined = Vec::with_capacity(NONCE_SIZE + ciphertext.len());
    combined.extend_from_slice(&nonce);
    combined.extend_from_slice(&ciphertext);

    Ok((ephemeral_public.to_bytes(), combined))
}

/// Decrypt data encrypted for this device using hybrid encryption.
///
/// This function:
/// 1. Computes the shared secret via ECDH using the device's private key
/// 2. Derives the same symmetric key using HKDF-SHA256
/// 3. Decrypts the ciphertext with ChaCha20-Poly1305
///
/// # Arguments
/// * `ephemeral_public_key` - The sender's ephemeral public key (32 bytes)
/// * `encrypted_data` - The encrypted data: nonce(12) || ciphertext || tag(16)
/// * `device_private_key` - This device's X25519 private key (32 bytes)
/// * `session_id` - The session ID string, used as HKDF salt
///
/// # Returns
/// The decrypted plaintext on success.
pub fn decrypt_for_device(
    ephemeral_public_key: &[u8; KEY_SIZE],
    encrypted_data: &[u8],
    device_private_key: &[u8; KEY_SIZE],
    session_id: &str,
) -> CoreResult<Vec<u8>> {
    // Validate minimum length: nonce(12) + tag(16) = 28 bytes minimum
    if encrypted_data.len() < NONCE_SIZE + 16 {
        return Err(CoreError::Crypto(
            "Encrypted data too short (must be at least 28 bytes)".to_string(),
        ));
    }

    // 1. Compute shared secret via ECDH
    let device_secret = StaticSecret::from(*device_private_key);
    let ephemeral_public = PublicKey::from(*ephemeral_public_key);
    let shared_secret = device_secret.diffie_hellman(&ephemeral_public);

    // 2. Derive same symmetric key with HKDF-SHA256
    let hkdf = Hkdf::<Sha256>::new(Some(session_id.as_bytes()), shared_secret.as_bytes());
    let mut symmetric_key = [0u8; KEY_SIZE];
    hkdf.expand(HKDF_INFO, &mut symmetric_key)
        .map_err(|e| CoreError::Crypto(format!("HKDF expand failed: {e}")))?;

    // 3. Extract nonce and ciphertext
    let nonce = &encrypted_data[..NONCE_SIZE];
    let ciphertext = &encrypted_data[NONCE_SIZE..];

    // 4. Decrypt with ChaCha20-Poly1305
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&symmetric_key));
    cipher
        .decrypt(Nonce::from_slice(nonce), ciphertext)
        .map_err(|_| {
            CoreError::Crypto("Decryption failed: authentication tag mismatch".to_string())
        })
}

/// Generate a new X25519 keypair for device identity.
///
/// # Returns
/// A tuple of (private_key, public_key), each 32 bytes.
pub fn generate_keypair() -> ([u8; KEY_SIZE], [u8; KEY_SIZE]) {
    let private_key = StaticSecret::random_from_rng(rand::thread_rng());
    let public_key = PublicKey::from(&private_key);
    (private_key.to_bytes(), public_key.to_bytes())
}

/// Derive the public key from a private key.
///
/// # Arguments
/// * `private_key` - The X25519 private key (32 bytes)
///
/// # Returns
/// The corresponding X25519 public key (32 bytes).
pub fn public_key_from_private(private_key: &[u8; KEY_SIZE]) -> [u8; KEY_SIZE] {
    let secret = StaticSecret::from(*private_key);
    let public = PublicKey::from(&secret);
    public.to_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        // Generate a recipient keypair
        let (private_key, public_key) = generate_keypair();

        // Test data
        let plaintext = b"sess_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        let session_id = "550e8400-e29b-41d4-a716-446655440000";

        // Encrypt
        let (ephemeral_pub, encrypted) =
            encrypt_for_device(plaintext, &public_key, session_id).unwrap();

        // Decrypt
        let decrypted =
            decrypt_for_device(&ephemeral_pub, &encrypted, &private_key, session_id).unwrap();

        assert_eq!(plaintext.as_slice(), decrypted.as_slice());
    }

    #[test]
    fn test_different_session_id_fails() {
        let (private_key, public_key) = generate_keypair();

        let plaintext = b"test secret";
        let session_id1 = "session-1";
        let session_id2 = "session-2";

        // Encrypt with session_id1
        let (ephemeral_pub, encrypted) =
            encrypt_for_device(plaintext, &public_key, session_id1).unwrap();

        // Try to decrypt with session_id2 - should fail
        let result = decrypt_for_device(&ephemeral_pub, &encrypted, &private_key, session_id2);

        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("Decryption failed"));
    }

    #[test]
    fn test_wrong_private_key_fails() {
        let (_, public_key) = generate_keypair();
        let (wrong_private_key, _) = generate_keypair();

        let plaintext = b"test secret";
        let session_id = "test-session";

        let (ephemeral_pub, encrypted) =
            encrypt_for_device(plaintext, &public_key, session_id).unwrap();

        // Try to decrypt with wrong private key
        let result = decrypt_for_device(&ephemeral_pub, &encrypted, &wrong_private_key, session_id);

        assert!(result.is_err());
    }

    #[test]
    fn test_tampered_ciphertext_fails() {
        let (private_key, public_key) = generate_keypair();

        let plaintext = b"test secret";
        let session_id = "test-session";

        let (ephemeral_pub, mut encrypted) =
            encrypt_for_device(plaintext, &public_key, session_id).unwrap();

        // Tamper with the ciphertext
        if !encrypted.is_empty() {
            let last_idx = encrypted.len() - 1;
            encrypted[last_idx] ^= 0xFF;
        }

        let result = decrypt_for_device(&ephemeral_pub, &encrypted, &private_key, session_id);

        assert!(result.is_err());
    }

    #[test]
    fn test_short_encrypted_data_fails() {
        let (private_key, _) = generate_keypair();
        let (ephemeral_pub, _) = generate_keypair();

        // Data shorter than nonce + tag (28 bytes)
        let short_data = vec![0u8; 20];
        let session_id = "test-session";

        let result = decrypt_for_device(&ephemeral_pub, &short_data, &private_key, session_id);

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("too short"));
    }

    #[test]
    fn test_empty_plaintext() {
        let (private_key, public_key) = generate_keypair();

        let plaintext = b"";
        let session_id = "test-session";

        let (ephemeral_pub, encrypted) =
            encrypt_for_device(plaintext, &public_key, session_id).unwrap();

        let decrypted =
            decrypt_for_device(&ephemeral_pub, &encrypted, &private_key, session_id).unwrap();

        assert!(decrypted.is_empty());
    }

    #[test]
    fn test_generate_keypair_produces_different_keys() {
        let (priv1, pub1) = generate_keypair();
        let (priv2, pub2) = generate_keypair();

        // Keys should be different (with overwhelming probability)
        assert_ne!(priv1, priv2);
        assert_ne!(pub1, pub2);
    }

    #[test]
    fn test_public_key_from_private() {
        // Generate a keypair
        let (private_key, expected_public) = generate_keypair();

        // Derive public key from private
        let derived_public = public_key_from_private(&private_key);

        // Should match
        assert_eq!(derived_public, expected_public);
    }

    #[test]
    fn test_encrypt_decrypt_with_derived_public_key() {
        // Generate a keypair
        let (private_key, _) = generate_keypair();

        // Derive public key
        let public_key = public_key_from_private(&private_key);

        // Encrypt with derived public key
        let plaintext = b"test message";
        let session_id = "test-session";

        let (ephemeral_pub, encrypted) =
            encrypt_for_device(plaintext, &public_key, session_id).unwrap();

        // Decrypt with private key
        let decrypted =
            decrypt_for_device(&ephemeral_pub, &encrypted, &private_key, session_id).unwrap();

        assert_eq!(plaintext.as_slice(), decrypted.as_slice());
    }
}
