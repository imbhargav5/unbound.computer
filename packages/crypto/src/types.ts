/**
 * Key pair for X25519 asymmetric encryption
 */
export interface KeyPair {
  publicKey: Uint8Array;
  privateKey: Uint8Array;
}

/**
 * Encrypted message with nonce
 */
export interface EncryptedMessage {
  nonce: Uint8Array;
  ciphertext: Uint8Array;
}

/**
 * Key sizes in bytes
 */
export const KEY_SIZE = {
  MASTER_KEY: 32, // 256 bits
  SESSION_KEY: 32, // 256 bits
  X25519_PUBLIC: 32,
  X25519_PRIVATE: 32,
  XCHACHA20_NONCE: 24,
} as const;
