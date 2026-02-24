/**
 * Web-specific crypto utilities for browser environments
 *
 * These functions are designed for use in web sessions where a browser
 * needs to establish encrypted communication with a trusted device.
 */

import { sha256 } from "@noble/hashes/sha256";
import { toHex } from "./encoding.js";
import { deriveKey } from "./hkdf.js";

/**
 * Hash a session token using SHA-256
 * Used for storing session tokens securely (never store raw tokens)
 *
 * @param token - Raw session token
 * @returns Hex-encoded SHA-256 hash
 */
export function hashSessionToken(token: string): string {
  const tokenBytes = new TextEncoder().encode(token);
  const hash = sha256(tokenBytes);
  return toHex(hash);
}

/**
 * Generate a random session token for web sessions
 *
 * @returns Base64URL-encoded random token
 */
export function generateSessionToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

/**
 * Derive a web session key from the Master Key
 *
 * This key is used for encrypting messages between the web client
 * and other devices. It's derived per-session and has a shorter
 * lifetime than regular session keys.
 *
 * @param masterKey - 32-byte Master Key
 * @param webSessionId - Web session identifier
 * @returns 32-byte web session key
 */
export function deriveWebSessionKey(
  masterKey: Uint8Array,
  webSessionId: string
): Uint8Array {
  return deriveKey(masterKey, `unbound-web-session:${webSessionId}`);
}

/**
 * Create QR code data for web session authorization
 *
 * @param sessionId - Web session ID
 * @param publicKey - Web client's ephemeral X25519 public key (base64)
 * @param expiresAt - Expiration timestamp (Unix ms)
 * @returns JSON string for QR code
 */
export function createWebSessionQRData(
  sessionId: string,
  publicKey: string,
  expiresAt: number
): string {
  const data = {
    version: 1,
    type: "web-session",
    sessionId,
    publicKey,
    expiresAt,
    timestamp: Date.now(),
  };
  return JSON.stringify(data);
}

/**
 * Parse and validate web session QR code data
 *
 * @param qrData - JSON string from QR code
 * @returns Parsed QR data or null if invalid
 */
export function parseWebSessionQRData(qrData: string): {
  version: number;
  type: string;
  sessionId: string;
  publicKey: string;
  expiresAt: number;
  timestamp: number;
} | null {
  try {
    const data = JSON.parse(qrData);

    // Validate required fields
    if (
      typeof data.version !== "number" ||
      data.type !== "web-session" ||
      typeof data.sessionId !== "string" ||
      typeof data.publicKey !== "string" ||
      typeof data.expiresAt !== "number" ||
      typeof data.timestamp !== "number"
    ) {
      return null;
    }

    // Check version
    if (data.version !== 1) {
      return null;
    }

    // Check expiration
    if (data.expiresAt < Date.now()) {
      return null;
    }

    return data;
  } catch {
    return null;
  }
}

/**
 * Check if running in a browser environment
 */
export function isBrowser(): boolean {
  return (
    typeof window !== "undefined" &&
    typeof window.crypto !== "undefined" &&
    typeof window.crypto.getRandomValues === "function"
  );
}

/**
 * Check if running in a secure context (HTTPS or localhost)
 */
export function isSecureContext(): boolean {
  if (!isBrowser()) {
    return false;
  }
  return window.isSecureContext === true;
}

// Helper function for base64url encoding
function base64UrlEncode(bytes: Uint8Array): string {
  const base64 = btoa(String.fromCharCode(...bytes));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * Calculate SHA-256 hash of arbitrary data
 *
 * @param data - Data to hash
 * @returns SHA-256 hash as Uint8Array
 */
export function sha256Hash(data: Uint8Array): Uint8Array {
  return sha256(data);
}

/**
 * Web session authorization data structure
 */
export interface WebSessionAuthData {
  /** Authorizing device ID */
  deviceId: string;
  /** Encrypted session key (base64) */
  encryptedSessionKey: string;
  /** Authorizing device's ephemeral public key (base64) */
  responderPublicKey: string;
  /** Web session ID */
  sessionId: string;
}

/**
 * Web session info for the client
 */
export interface WebSessionInfo {
  /** When the session was created */
  createdAt: Date;
  /** Encrypted session key (only present when active) */
  encryptedSessionKey?: string;
  /** When the session expires */
  expiresAt: Date;
  /** Session ID */
  id: string;
  /** Ephemeral public key (base64) */
  publicKey: string;
  /** Responder public key (only present when active) */
  responderPublicKey?: string;
  /** Current status */
  status: "pending" | "active" | "expired" | "revoked";
}
