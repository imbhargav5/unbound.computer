/**
 * Pairing Initiator V2 - Device-Rooted Trust Model
 *
 * The initiator is the device requesting to be paired (e.g., Mac requesting pairing with Phone).
 * Unlike v1, this does NOT receive a Master Key. Instead, it:
 * 1. Displays QR code with its long-term device public key
 * 2. Receives the responder's device identity
 * 3. Computes a pairwise secret for future communication
 */

import {
  computePairwiseSecret,
  fromBase64,
  generateKeyPair,
  toBase64,
} from "@unbound/crypto";
import type {
  DeviceRole,
  PairingQRDataV2,
  PairingResponseV2,
  PairingResultV2,
  PairingSessionV2,
  TrustedDeviceInfo,
} from "./types.js";

/**
 * Default pairing session timeout (5 minutes)
 */
const DEFAULT_PAIRING_TIMEOUT = 5 * 60 * 1000;

/**
 * Options for creating a v2 pairing session
 */
export interface CreatePairingSessionV2Options {
  /** This device's UUID */
  deviceId: string;
  /** This device's human-readable name */
  deviceName: string;
  /** This device's role (typically "trusted_executor" for Mac) */
  deviceRole: DeviceRole;
  /** This device's long-term key pair */
  deviceKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array };
  /** The user's account ID */
  accountId: string;
  /** Session timeout in milliseconds (default: 5 minutes) */
  timeoutMs?: number;
}

/**
 * Create a new v2 pairing session for the initiating device
 */
export function createPairingSessionV2(
  options: CreatePairingSessionV2Options
): PairingSessionV2 {
  const ephemeralKeyPair = generateKeyPair();
  const now = new Date();
  const timeoutMs = options.timeoutMs ?? DEFAULT_PAIRING_TIMEOUT;

  return {
    id: crypto.randomUUID(),
    state: "idle",
    deviceKeyPair: options.deviceKeyPair,
    ephemeralKeyPair,
    deviceId: options.deviceId,
    deviceName: options.deviceName,
    deviceRole: options.deviceRole,
    accountId: options.accountId,
    createdAt: now,
    expiresAt: new Date(now.getTime() + timeoutMs),
  };
}

/**
 * Generate QR code data for the v2 pairing session
 */
export function generatePairingQRDataV2(
  session: PairingSessionV2
): PairingQRDataV2 {
  return {
    version: 2,
    deviceId: session.deviceId,
    deviceName: session.deviceName,
    deviceRole: session.deviceRole,
    devicePublicKey: toBase64(session.deviceKeyPair.publicKey),
    ephemeralPublicKey: toBase64(session.ephemeralKeyPair.publicKey),
    timestamp: Date.now(),
    accountId: session.accountId,
  };
}

/**
 * Serialize QR data to string for display
 */
export function serializePairingQRDataV2(data: PairingQRDataV2): string {
  return JSON.stringify(data);
}

/**
 * Process the pairing response from the trust root device
 *
 * This establishes mutual trust without transferring a Master Key.
 * Instead, it computes a pairwise secret for device-to-device encryption.
 *
 * @param session - The current pairing session
 * @param response - The response from the responder device
 */
export function processPairingResponseV2(
  session: PairingSessionV2,
  response: PairingResponseV2
): PairingResultV2 {
  try {
    // Verify the response is recent (within 5 minutes)
    const responseAge = Date.now() - response.timestamp;
    if (responseAge > 5 * 60 * 1000) {
      return {
        success: false,
        error: "Pairing response has expired",
      };
    }

    // Extract the responder's long-term public key
    const responderPublicKey = fromBase64(response.devicePublicKey);

    // Compute pairwise secret using our private key and their public key
    // This is the shared secret that will be used for all future communication
    const pairwiseResult = computePairwiseSecret(
      session.deviceKeyPair.privateKey,
      responderPublicKey
    );

    // Create trusted device info
    const trustedDevice: TrustedDeviceInfo = {
      deviceId: response.deviceId,
      deviceName: response.deviceName,
      deviceRole: response.deviceRole,
      publicKey: response.devicePublicKey,
      trustedAt: new Date(),
    };

    return {
      success: true,
      trustedDevice,
      pairwiseSecret: pairwiseResult.secret,
    };
  } catch (error) {
    return {
      success: false,
      error:
        error instanceof Error
          ? error.message
          : "Failed to process pairing response",
    };
  }
}

/**
 * Check if a v2 pairing session has expired
 */
export function isPairingSessionV2Expired(session: PairingSessionV2): boolean {
  return new Date() > session.expiresAt;
}

/**
 * Update v2 pairing session state
 */
export function updatePairingSessionV2State(
  session: PairingSessionV2,
  state: PairingSessionV2["state"],
  pairedDevice?: TrustedDeviceInfo,
  error?: string
): PairingSessionV2 {
  return {
    ...session,
    state,
    pairedDevice,
    error,
  };
}
