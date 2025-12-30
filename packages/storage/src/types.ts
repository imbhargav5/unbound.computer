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
  MASTER_KEY: "master_key",
  DEVICE_ID: "device_id",
  DEVICE_PRIVATE_KEY: "device_private_key",
  API_KEY: "api_key",
  DEVICE_FINGERPRINT: "device_fingerprint",
} as const;

export type StorageKey = (typeof STORAGE_KEYS)[keyof typeof STORAGE_KEYS];
