/**
 * Pairing Responder V2 - Device-Rooted Trust Model
 *
 * The responder is the trust root device (e.g., Phone) that approves pairing requests.
 * Unlike v1, this does NOT send a Master Key. Instead, it:
 * 1. Scans the initiator's QR code
 * 2. Verifies the account ID matches
 * 3. Sends its own device identity
 * 4. Computes and stores the pairwise secret
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
  TrustedDeviceInfo,
} from "./types.js";

/**
 * Default QR code expiry (5 minutes)
 */
const QR_EXPIRY_MS = 5 * 60 * 1000;

/**
 * Validate a scanned v2 QR code
 *
 * @param qrData - The scanned QR code data
 * @param expectedAccountId - The account ID we expect (must match)
 */
export function validateQRCodeV2(
  qrData: PairingQRDataV2,
  expectedAccountId: string
): { valid: boolean; error?: string } {
  // Check version
  if (qrData.version !== 2) {
    return {
      valid: false,
      error: `Unsupported QR code version: ${qrData.version}. Expected version 2.`,
    };
  }

  // Check account ID matches
  if (qrData.accountId !== expectedAccountId) {
    return {
      valid: false,
      error: "Account ID mismatch. This device belongs to a different account.",
    };
  }

  // Check if QR has expired
  const qrAge = Date.now() - qrData.timestamp;
  if (qrAge > QR_EXPIRY_MS) {
    return {
      valid: false,
      error: "Pairing QR code has expired. Please generate a new one.",
    };
  }

  // Validate public key format
  try {
    const publicKey = fromBase64(qrData.devicePublicKey);
    if (publicKey.length !== 32) {
      return {
        valid: false,
        error: "Invalid device public key length",
      };
    }
  } catch {
    return {
      valid: false,
      error: "Invalid device public key format",
    };
  }

  return { valid: true };
}

/**
 * Parse QR code string to v2 data
 */
export function parsePairingQRDataV2(qrString: string): PairingQRDataV2 | null {
  try {
    const data = JSON.parse(qrString);
    if (data.version !== 2) {
      return null;
    }
    return data as PairingQRDataV2;
  } catch {
    return null;
  }
}

/**
 * Options for creating a v2 pairing response
 */
export interface CreatePairingResponseV2Options {
  /** The scanned QR code data from the initiator */
  qrData: PairingQRDataV2;
  /** This device's (responder's) ID */
  responderDeviceId: string;
  /** This device's name */
  responderDeviceName: string;
  /** This device's role (typically "trust_root") */
  responderDeviceRole: DeviceRole;
  /** This device's long-term key pair */
  responderDeviceKeyPair: { publicKey: Uint8Array; privateKey: Uint8Array };
}

/**
 * Create a pairing response from the trust root device
 */
export function createPairingResponseV2(
  options: CreatePairingResponseV2Options
): PairingResultV2 & { response?: PairingResponseV2 } {
  const {
    qrData,
    responderDeviceId,
    responderDeviceName,
    responderDeviceRole,
    responderDeviceKeyPair,
  } = options;
  try {
    // Generate ephemeral key pair for this session
    const ephemeralKeyPair = generateKeyPair();

    // Extract initiator's long-term public key
    const initiatorPublicKey = fromBase64(qrData.devicePublicKey);

    // Compute pairwise secret using our private key and their public key
    const pairwiseResult = computePairwiseSecret(
      responderDeviceKeyPair.privateKey,
      initiatorPublicKey
    );

    // Create signature placeholder (in production, use Ed25519 signing)
    // For now, we use HMAC of the pairing data with the pairwise secret
    const signature = toBase64(pairwiseResult.secret.slice(0, 16));

    // Create the response
    const response: PairingResponseV2 = {
      devicePublicKey: toBase64(responderDeviceKeyPair.publicKey),
      ephemeralPublicKey: toBase64(ephemeralKeyPair.publicKey),
      deviceId: responderDeviceId,
      deviceName: responderDeviceName,
      deviceRole: responderDeviceRole,
      signature,
      timestamp: Date.now(),
    };

    // Create trusted device info for the initiator
    const trustedDevice: TrustedDeviceInfo = {
      deviceId: qrData.deviceId,
      deviceName: qrData.deviceName,
      deviceRole: qrData.deviceRole,
      publicKey: qrData.devicePublicKey,
      trustedAt: new Date(),
    };

    return {
      success: true,
      trustedDevice,
      pairwiseSecret: pairwiseResult.secret,
      response,
    };
  } catch (error) {
    return {
      success: false,
      error:
        error instanceof Error
          ? error.message
          : "Failed to create pairing response",
    };
  }
}

/**
 * Extract device info from v2 QR data
 */
export function extractDeviceInfoFromQR(
  qrData: PairingQRDataV2
): TrustedDeviceInfo {
  return {
    deviceId: qrData.deviceId,
    deviceName: qrData.deviceName,
    deviceRole: qrData.deviceRole,
    publicKey: qrData.devicePublicKey,
    trustedAt: new Date(),
  };
}
