import { fromBase64, toBase64 } from "@unbound/crypto";
import type { PairingQRData } from "./types.js";

/**
 * Generate QR code data for pairing
 */
export function generateQRData(
  deviceId: string,
  deviceName: string,
  publicKey: Uint8Array
): PairingQRData {
  return {
    version: 1,
    deviceId,
    deviceName,
    publicKey: toBase64(publicKey),
    timestamp: Date.now(),
  };
}

/**
 * Serialize QR data to string for encoding in QR code
 */
export function serializeQRData(data: PairingQRData): string {
  return JSON.stringify(data);
}

/**
 * Parse QR data from scanned string
 */
export function parseQRData(qrString: string): PairingQRData | null {
  try {
    const data = JSON.parse(qrString) as PairingQRData;

    // Validate required fields
    if (
      data.version !== 1 ||
      typeof data.deviceId !== "string" ||
      typeof data.deviceName !== "string" ||
      typeof data.publicKey !== "string" ||
      typeof data.timestamp !== "number"
    ) {
      return null;
    }

    return data;
  } catch {
    return null;
  }
}

/**
 * Extract public key from QR data
 */
export function extractPublicKey(data: PairingQRData): Uint8Array {
  return fromBase64(data.publicKey);
}

/**
 * Check if QR data has expired (default: 5 minutes)
 */
export function isQRDataExpired(
  data: PairingQRData,
  maxAgeMs = 5 * 60 * 1000
): boolean {
  return Date.now() - data.timestamp > maxAgeMs;
}
