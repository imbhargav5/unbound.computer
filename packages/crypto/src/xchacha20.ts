import { xchacha20poly1305 } from "@noble/ciphers/chacha";
import { randomBytes } from "./random.js";
import type { EncryptedMessage } from "./types.js";
import { KEY_SIZE } from "./types.js";

/**
 * Encrypt plaintext using XChaCha20-Poly1305
 *
 * @param key - 32-byte encryption key
 * @param plaintext - Data to encrypt
 * @returns Encrypted message with nonce and ciphertext
 */
export function encrypt(
  key: Uint8Array,
  plaintext: Uint8Array
): EncryptedMessage {
  if (key.length !== KEY_SIZE.SESSION_KEY) {
    throw new Error(`Key must be ${KEY_SIZE.SESSION_KEY} bytes`);
  }

  const nonce = randomBytes(KEY_SIZE.XCHACHA20_NONCE);
  const cipher = xchacha20poly1305(key, nonce);
  const ciphertext = cipher.encrypt(plaintext);

  return { nonce, ciphertext };
}

/**
 * Decrypt ciphertext using XChaCha20-Poly1305
 *
 * @param key - 32-byte encryption key
 * @param nonce - 24-byte nonce used for encryption
 * @param ciphertext - Encrypted data
 * @returns Decrypted plaintext
 * @throws Error if decryption fails (authentication tag mismatch)
 */
export function decrypt(
  key: Uint8Array,
  nonce: Uint8Array,
  ciphertext: Uint8Array
): Uint8Array {
  if (key.length !== KEY_SIZE.SESSION_KEY) {
    throw new Error(`Key must be ${KEY_SIZE.SESSION_KEY} bytes`);
  }

  if (nonce.length !== KEY_SIZE.XCHACHA20_NONCE) {
    throw new Error(`Nonce must be ${KEY_SIZE.XCHACHA20_NONCE} bytes`);
  }

  const cipher = xchacha20poly1305(key, nonce);
  return cipher.decrypt(ciphertext);
}

/**
 * Encrypt plaintext and return combined nonce + ciphertext
 *
 * @param key - 32-byte encryption key
 * @param plaintext - Data to encrypt
 * @returns Combined nonce (24 bytes) + ciphertext
 */
export function encryptSealed(
  key: Uint8Array,
  plaintext: Uint8Array
): Uint8Array {
  const { nonce, ciphertext } = encrypt(key, plaintext);
  const sealed = new Uint8Array(nonce.length + ciphertext.length);
  sealed.set(nonce);
  sealed.set(ciphertext, nonce.length);
  return sealed;
}

/**
 * Decrypt combined nonce + ciphertext
 *
 * @param key - 32-byte encryption key
 * @param sealed - Combined nonce + ciphertext
 * @returns Decrypted plaintext
 */
export function decryptSealed(key: Uint8Array, sealed: Uint8Array): Uint8Array {
  const nonce = sealed.slice(0, KEY_SIZE.XCHACHA20_NONCE);
  const ciphertext = sealed.slice(KEY_SIZE.XCHACHA20_NONCE);
  return decrypt(key, nonce, ciphertext);
}
