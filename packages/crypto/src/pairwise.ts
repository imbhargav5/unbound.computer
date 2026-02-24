/**
 * Pairwise Cryptographic Primitives
 *
 * Device-rooted trust model where each device pair shares a unique pairwise secret.
 * PairSecret_AB = ECDH(priv_A, pub_B)
 *
 * Session keys are derived from pairwise secrets using HKDF.
 */

import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha256";
import { randomBytes } from "./random.js";
import { KEY_SIZE } from "./types.js";
import { computeSharedSecret } from "./x25519.js";

/**
 * Context string for session key derivation
 */
export const PAIRWISE_CONTEXT = {
  SESSION: "unbound-session-v1",
  MESSAGE: "unbound-message-v1",
  WEB_SESSION: "unbound-web-session-v1",
} as const;

/**
 * Pairwise secret between two devices
 */
export interface PairwiseSecret {
  /** ID of device A (smaller UUID for consistent ordering) */
  deviceAId?: string;
  /** ID of device B (larger UUID for consistent ordering) */
  deviceBId?: string;
  /** Raw 32-byte shared secret from X25519 ECDH */
  secret: Uint8Array;
}

/**
 * Compute pairwise secret between two devices using X25519 ECDH
 *
 * The pairwise secret is the same regardless of which device initiates:
 * ECDH(priv_A, pub_B) === ECDH(priv_B, pub_A)
 *
 * @param myPrivateKey - Our X25519 private key (32 bytes)
 * @param theirPublicKey - Their X25519 public key (32 bytes)
 * @returns Pairwise secret (32-byte shared secret)
 */
export function computePairwiseSecret(
  myPrivateKey: Uint8Array,
  theirPublicKey: Uint8Array
): PairwiseSecret {
  const secret = computeSharedSecret(myPrivateKey, theirPublicKey);
  return { secret };
}

/**
 * Derive a session key from a pairwise secret
 *
 * Uses HKDF-SHA256 with:
 * - IKM: pairwise secret
 * - Salt: session ID as bytes
 * - Info: context string
 *
 * @param pairwiseSecret - Pairwise secret between devices
 * @param sessionId - Unique session identifier (e.g., UUID)
 * @param context - Context string (default: "unbound-session-v1")
 * @returns 32-byte session key
 */
export function deriveSessionKeyFromPair(
  pairwiseSecret: PairwiseSecret | Uint8Array,
  sessionId: string,
  context: string = PAIRWISE_CONTEXT.SESSION
): Uint8Array {
  const secret =
    pairwiseSecret instanceof Uint8Array
      ? pairwiseSecret
      : pairwiseSecret.secret;

  if (secret.length !== KEY_SIZE.SESSION_KEY) {
    throw new Error(`Pairwise secret must be ${KEY_SIZE.SESSION_KEY} bytes`);
  }

  const salt = new TextEncoder().encode(sessionId);
  const info = new TextEncoder().encode(context);

  return hkdf(sha256, secret, salt, info, KEY_SIZE.SESSION_KEY);
}

/**
 * Derive a message key for a specific purpose
 *
 * Use this for deriving keys for specific message types or operations.
 *
 * @param pairwiseSecret - Pairwise secret between devices
 * @param purpose - Purpose identifier (e.g., "control", "stream", "ack")
 * @param counter - Optional counter for key rotation (default: 0)
 * @returns 32-byte message key
 */
export function deriveMessageKey(
  pairwiseSecret: PairwiseSecret | Uint8Array,
  purpose: string,
  counter = 0
): Uint8Array {
  const secret =
    pairwiseSecret instanceof Uint8Array
      ? pairwiseSecret
      : pairwiseSecret.secret;

  if (secret.length !== KEY_SIZE.SESSION_KEY) {
    throw new Error(`Pairwise secret must be ${KEY_SIZE.SESSION_KEY} bytes`);
  }

  // Include counter in info for key rotation
  const info = new TextEncoder().encode(
    `${PAIRWISE_CONTEXT.MESSAGE}:${purpose}:${counter}`
  );

  return hkdf(sha256, secret, new Uint8Array(0), info, KEY_SIZE.SESSION_KEY);
}

/**
 * Generate a random 256-bit session key for web sessions
 *
 * Web sessions use random keys (not derived from pairwise secrets)
 * because they are temporary and don't have long-term device keys.
 * The authorizing device generates this key and encrypts it for the web client.
 *
 * @returns 32-byte random session key
 */
export function generateSessionKey(): Uint8Array {
  return randomBytes(KEY_SIZE.SESSION_KEY);
}

/**
 * Derive a web session key from an authorizing device's pairwise context
 *
 * This is used when the authorizing device wants to bind the web session
 * to a specific session context for additional security.
 *
 * @param devicePrivateKey - Authorizing device's private key
 * @param webPublicKey - Web client's ephemeral public key
 * @param sessionId - Web session ID
 * @returns 32-byte session key
 */
export function deriveWebSessionKeyFromDevice(
  devicePrivateKey: Uint8Array,
  webPublicKey: Uint8Array,
  sessionId: string
): Uint8Array {
  // Compute ephemeral shared secret with web client
  const sharedSecret = computeSharedSecret(devicePrivateKey, webPublicKey);

  // Derive session key with web session context
  const salt = new TextEncoder().encode(sessionId);
  const info = new TextEncoder().encode(PAIRWISE_CONTEXT.WEB_SESSION);

  return hkdf(sha256, sharedSecret, salt, info, KEY_SIZE.SESSION_KEY);
}

/**
 * Order device IDs consistently for pairwise secret storage
 *
 * Ensures device_a_id < device_b_id for database consistency.
 *
 * @param deviceId1 - First device ID
 * @param deviceId2 - Second device ID
 * @returns Tuple of [smaller_id, larger_id]
 */
export function orderDeviceIds(
  deviceId1: string,
  deviceId2: string
): [string, string] {
  return deviceId1 < deviceId2
    ? [deviceId1, deviceId2]
    : [deviceId2, deviceId1];
}
