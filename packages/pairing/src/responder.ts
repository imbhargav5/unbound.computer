import {
  computeSharedSecret,
  deriveKey,
  encrypt,
  generateKeyPair,
  toBase64,
} from "@unbound/crypto";
import { extractPublicKey, isQRDataExpired } from "./qr.js";
import type { PairingQRData, PairingResult } from "./types.js";

/**
 * Response from the trusted device to send to the new device
 */
export interface PairingResponseData {
  encryptedMasterKey: string;
  nonce: string;
  responderPublicKey: Uint8Array;
}

/**
 * Process a scanned QR code and encrypt the Master Key for the new device
 *
 * @param qrData - The scanned QR code data
 * @param masterKey - The Master Key to share
 * @returns The encrypted response to send to the new device
 */
export function createPairingResponse(
  qrData: PairingQRData,
  masterKey: Uint8Array
): PairingResult & { response?: PairingResponseData } {
  // Check if QR data has expired
  if (isQRDataExpired(qrData)) {
    return {
      success: false,
      error: "Pairing QR code has expired",
    };
  }

  try {
    // Extract the new device's public key
    const newDevicePublicKey = extractPublicKey(qrData);

    // Generate ephemeral keypair for the response
    const responderKeyPair = generateKeyPair();

    // Compute shared secret using X25519
    const sharedSecret = computeSharedSecret(
      responderKeyPair.privateKey,
      newDevicePublicKey
    );

    // Derive encryption key from shared secret
    const encryptionKey = deriveKey(sharedSecret, "pairing");

    // Encrypt the Master Key
    const { nonce, ciphertext } = encrypt(encryptionKey, masterKey);

    return {
      success: true,
      response: {
        encryptedMasterKey: toBase64(ciphertext),
        nonce: toBase64(nonce),
        responderPublicKey: responderKeyPair.publicKey,
      },
    };
  } catch (error) {
    return {
      success: false,
      error:
        error instanceof Error ? error.message : "Failed to encrypt Master Key",
    };
  }
}

/**
 * Validate a scanned QR code
 */
export function validateQRCode(qrData: PairingQRData): {
  valid: boolean;
  error?: string;
} {
  if (qrData.version !== 1) {
    return {
      valid: false,
      error: `Unsupported QR code version: ${qrData.version}`,
    };
  }

  if (isQRDataExpired(qrData)) {
    return {
      valid: false,
      error: "Pairing QR code has expired",
    };
  }

  try {
    const publicKey = extractPublicKey(qrData);
    if (publicKey.length !== 32) {
      return {
        valid: false,
        error: "Invalid public key length",
      };
    }
  } catch {
    return {
      valid: false,
      error: "Invalid public key format",
    };
  }

  return { valid: true };
}
