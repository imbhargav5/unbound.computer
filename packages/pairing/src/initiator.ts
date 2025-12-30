import {
  computeSharedSecret,
  decrypt,
  deriveKey,
  fromBase64,
  generateKeyPair,
} from "@unbound/crypto";
import { generateQRData, serializeQRData } from "./qr.js";
import type { PairingQRData, PairingResult, PairingSession } from "./types.js";

/**
 * Default pairing session timeout (5 minutes)
 */
const DEFAULT_PAIRING_TIMEOUT = 5 * 60 * 1000;

/**
 * Create a new pairing session for the new device
 * This generates an ephemeral keypair and prepares the QR code data
 */
export function createPairingSession(
  deviceId: string,
  deviceName: string,
  timeoutMs = DEFAULT_PAIRING_TIMEOUT
): PairingSession {
  const ephemeralKeyPair = generateKeyPair();
  const now = new Date();

  return {
    id: crypto.randomUUID(),
    state: "idle",
    ephemeralKeyPair,
    deviceId,
    deviceName,
    createdAt: now,
    expiresAt: new Date(now.getTime() + timeoutMs),
  };
}

/**
 * Generate QR code string for the pairing session
 */
export function generatePairingQR(session: PairingSession): string {
  const qrData = generateQRData(
    session.deviceId,
    session.deviceName,
    session.ephemeralKeyPair.publicKey
  );
  return serializeQRData(qrData);
}

/**
 * Get QR data object for the pairing session
 */
export function getPairingQRData(session: PairingSession): PairingQRData {
  return generateQRData(
    session.deviceId,
    session.deviceName,
    session.ephemeralKeyPair.publicKey
  );
}

/**
 * Process the pairing response from the trusted device
 */
export function processPairingResponse(
  session: PairingSession,
  encryptedMasterKey: string,
  nonce: string,
  trustedDevicePublicKey: Uint8Array
): PairingResult {
  try {
    // Compute shared secret using X25519
    const sharedSecret = computeSharedSecret(
      session.ephemeralKeyPair.privateKey,
      trustedDevicePublicKey
    );

    // Derive encryption key from shared secret
    const encryptionKey = deriveKey(sharedSecret, "pairing");

    // Decrypt the Master Key
    const encryptedBytes = fromBase64(encryptedMasterKey);
    const nonceBytes = fromBase64(nonce);
    const masterKey = decrypt(encryptionKey, nonceBytes, encryptedBytes);

    return {
      success: true,
      masterKey,
      deviceId: session.deviceId,
    };
  } catch (error) {
    return {
      success: false,
      error:
        error instanceof Error ? error.message : "Failed to decrypt Master Key",
    };
  }
}

/**
 * Check if a pairing session has expired
 */
export function isPairingSessionExpired(session: PairingSession): boolean {
  return new Date() > session.expiresAt;
}

/**
 * Update pairing session state
 */
export function updatePairingSessionState(
  session: PairingSession,
  state: PairingSession["state"],
  masterKey?: Uint8Array,
  error?: string
): PairingSession {
  return {
    ...session,
    state,
    masterKey,
    error,
  };
}
