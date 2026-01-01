/**
 * Storage adapter interface for secure key storage
 */
export interface SecureStorage {
  /**
   * Store a value securely
   */
  set(key: string, value: string): Promise<void>;

  /**
   * Retrieve a value
   */
  get(key: string): Promise<string | null>;

  /**
   * Delete a value
   */
  delete(key: string): Promise<boolean>;

  /**
   * Check if a key exists
   */
  has(key: string): Promise<boolean>;
}

/**
 * Storage keys used by the CLI
 */
export const STORAGE_KEYS = {
  /** @deprecated Use trusted devices instead of shared Master Key */
  MASTER_KEY: "master_key",
  DEVICE_ID: "device_id",
  DEVICE_PRIVATE_KEY: "device_private_key",
  API_KEY: "api_key",
  DEVICE_FINGERPRINT: "device_fingerprint",
  /** JSON array of trusted device info */
  TRUSTED_DEVICES: "trusted_devices",
} as const;

export type StorageKey = (typeof STORAGE_KEYS)[keyof typeof STORAGE_KEYS];

/**
 * Information about a trusted device
 */
export interface TrustedDevice {
  /** Device UUID from the database */
  deviceId: string;
  /** Device name for display */
  name: string;
  /** Device's long-term X25519 public key (base64) */
  publicKey: string;
  /** Device role in trust hierarchy */
  role: "trust_root" | "trusted_executor" | "temporary_viewer";
  /** When trust was established */
  trustedAt: string;
  /** When trust expires (optional) */
  expiresAt?: string;
}
