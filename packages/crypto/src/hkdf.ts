import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha256";
import { randomBytes } from "./random.js";
import { KEY_SIZE } from "./types.js";

/**
 * Generate a new 256-bit Master Key
 *
 * @returns 32-byte random Master Key
 */
export function generateMasterKey(): Uint8Array {
  return randomBytes(KEY_SIZE.MASTER_KEY);
}

/**
 * Derive a session key from the Master Key using HKDF-SHA256
 *
 * @param masterKey - 32-byte Master Key
 * @param sessionId - Session identifier used as info parameter
 * @param salt - Optional salt (if not provided, uses empty salt)
 * @returns 32-byte session key
 */
export function deriveSessionKey(
  masterKey: Uint8Array,
  sessionId: string,
  salt?: Uint8Array
): Uint8Array {
  if (masterKey.length !== KEY_SIZE.MASTER_KEY) {
    throw new Error(`Master Key must be ${KEY_SIZE.MASTER_KEY} bytes`);
  }

  const info = new TextEncoder().encode(sessionId);
  return hkdf(
    sha256,
    masterKey,
    salt ?? new Uint8Array(0),
    info,
    KEY_SIZE.SESSION_KEY
  );
}

/**
 * Derive a key from a shared secret using HKDF-SHA256
 *
 * @param sharedSecret - Shared secret from X25519 DH
 * @param info - Context info (e.g., "pairing" or "message")
 * @param salt - Optional salt
 * @param length - Desired key length (default: 32 bytes)
 * @returns Derived key
 */
export function deriveKey(
  sharedSecret: Uint8Array,
  info: string,
  salt?: Uint8Array,
  length = KEY_SIZE.SESSION_KEY
): Uint8Array {
  const infoBytes = new TextEncoder().encode(info);
  return hkdf(
    sha256,
    sharedSecret,
    salt ?? new Uint8Array(0),
    infoBytes,
    length
  );
}
