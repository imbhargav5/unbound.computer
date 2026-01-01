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
 * @deprecated Use PairingSessionV2 for device-rooted trust model
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
 * QR code data for pairing (v1 - Master Key transfer)
 * @deprecated Use PairingQRDataV2 for device-rooted trust model
 */
export interface PairingQRData {
  version: 1;
  deviceId: string;
  deviceName: string;
  publicKey: string; // Base64-encoded ephemeral public key
  timestamp: number;
}

/**
 * Pairing result (v1)
 * @deprecated Use PairingResultV2 for device-rooted trust model
 */
export interface PairingResult {
  success: boolean;
  masterKey?: Uint8Array;
  deviceId?: string;
  error?: string;
}

// ==========================================
// Protocol V2 - Device-Rooted Trust Model
// ==========================================

/**
 * Device role in trust hierarchy
 */
export type DeviceRole = "trust_root" | "trusted_executor" | "temporary_viewer";

/**
 * QR code data for pairing (v2 - Identity exchange, no Master Key)
 */
export interface PairingQRDataV2 {
  version: 2;
  /** Device UUID */
  deviceId: string;
  /** Human-readable device name */
  deviceName: string;
  /** Device role in trust hierarchy */
  deviceRole: DeviceRole;
  /** Long-term X25519 public key (base64) */
  devicePublicKey: string;
  /** Ephemeral public key for this pairing session (base64) */
  ephemeralPublicKey: string;
  /** Unix timestamp when QR was generated */
  timestamp: number;
  /** User account ID for verification */
  accountId: string;
}

/**
 * Pairing session for v2 protocol
 */
export interface PairingSessionV2 {
  id: string;
  state: PairingState;
  /** Our long-term device key pair */
  deviceKeyPair: KeyPair;
  /** Ephemeral key pair for this pairing session */
  ephemeralKeyPair: KeyPair;
  /** Our device ID */
  deviceId: string;
  /** Our device name */
  deviceName: string;
  /** Our device role */
  deviceRole: DeviceRole;
  /** Our account ID */
  accountId: string;
  createdAt: Date;
  expiresAt: Date;
  /** Paired device info (populated after successful pairing) */
  pairedDevice?: TrustedDeviceInfo;
  error?: string;
}

/**
 * Information about a trusted device after pairing
 */
export interface TrustedDeviceInfo {
  deviceId: string;
  deviceName: string;
  deviceRole: DeviceRole;
  /** Long-term public key (base64) */
  publicKey: string;
  /** When trust was established */
  trustedAt: Date;
}

/**
 * Result of v2 pairing (identity exchange, not Master Key)
 */
export interface PairingResultV2 {
  success: boolean;
  /** The newly trusted device */
  trustedDevice?: TrustedDeviceInfo;
  /** Computed pairwise secret (only in memory, never stored directly) */
  pairwiseSecret?: Uint8Array;
  error?: string;
}

/**
 * Response from the authorizing device (trust root) to the requesting device
 */
export interface PairingResponseV2 {
  /** Authorizing device's long-term public key (base64) */
  devicePublicKey: string;
  /** Authorizing device's ephemeral public key for this session (base64) */
  ephemeralPublicKey: string;
  /** Authorizing device's ID */
  deviceId: string;
  /** Authorizing device's name */
  deviceName: string;
  /** Authorizing device's role */
  deviceRole: DeviceRole;
  /** Signature over the pairing data (proves ownership of private key) */
  signature: string;
  /** Timestamp of response */
  timestamp: number;
}
