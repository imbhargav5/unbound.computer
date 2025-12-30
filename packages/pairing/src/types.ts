import type { KeyPair } from "@unbound/crypto";

/**
 * State of the pairing process
 */
export type PairingState =
  | "idle"
  | "waiting_for_scan"
  | "waiting_for_response"
  | "completed"
  | "failed";

/**
 * Pairing session for the new device (the one requesting pairing)
 */
export interface PairingSession {
  id: string;
  state: PairingState;
  ephemeralKeyPair: KeyPair;
  deviceId: string;
  deviceName: string;
  createdAt: Date;
  expiresAt: Date;
  masterKey?: Uint8Array;
  error?: string;
}

/**
 * QR code data for pairing
 */
export interface PairingQRData {
  version: 1;
  deviceId: string;
  deviceName: string;
  publicKey: string; // Base64-encoded
  timestamp: number;
}

/**
 * Pairing result
 */
export interface PairingResult {
  success: boolean;
  masterKey?: Uint8Array;
  deviceId?: string;
  error?: string;
}
