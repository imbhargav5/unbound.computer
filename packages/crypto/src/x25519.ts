import { x25519 } from "@noble/curves/ed25519";
import { randomBytes } from "./random.js";
import type { KeyPair } from "./types.js";
import { KEY_SIZE } from "./types.js";

/**
 * Generate a new X25519 key pair for asymmetric encryption
 *
 * @returns Key pair with public and private keys
 */
export function generateKeyPair(): KeyPair {
  const privateKey = randomBytes(KEY_SIZE.X25519_PRIVATE);
  const publicKey = x25519.getPublicKey(privateKey);
  return { publicKey, privateKey };
}

/**
 * Generate public key from private key
 *
 * @param privateKey - 32-byte private key
 * @returns 32-byte public key
 */
export function getPublicKey(privateKey: Uint8Array): Uint8Array {
  if (privateKey.length !== KEY_SIZE.X25519_PRIVATE) {
    throw new Error(`Private key must be ${KEY_SIZE.X25519_PRIVATE} bytes`);
  }
  return x25519.getPublicKey(privateKey);
}

/**
 * Compute shared secret using X25519 Diffie-Hellman
 *
 * @param privateKey - Our private key
 * @param theirPublicKey - Their public key
 * @returns 32-byte shared secret
 */
export function computeSharedSecret(
  privateKey: Uint8Array,
  theirPublicKey: Uint8Array
): Uint8Array {
  if (privateKey.length !== KEY_SIZE.X25519_PRIVATE) {
    throw new Error(`Private key must be ${KEY_SIZE.X25519_PRIVATE} bytes`);
  }
  if (theirPublicKey.length !== KEY_SIZE.X25519_PUBLIC) {
    throw new Error(`Public key must be ${KEY_SIZE.X25519_PUBLIC} bytes`);
  }
  return x25519.getSharedSecret(privateKey, theirPublicKey);
}
