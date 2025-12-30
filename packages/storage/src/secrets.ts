import { fromBase64, toBase64 } from "@unbound/crypto";
import type { SecureStorage } from "./types.js";
import { STORAGE_KEYS } from "./types.js";

/**
 * High-level API for storing and retrieving secrets
 * Handles encoding/decoding of binary data
 */
export class SecretsManager {
  private storage: SecureStorage;

  constructor(storage: SecureStorage) {
    this.storage = storage;
  }

  /**
   * Store the Master Key
   */
  async setMasterKey(masterKey: Uint8Array): Promise<void> {
    await this.storage.set(STORAGE_KEYS.MASTER_KEY, toBase64(masterKey));
  }

  /**
   * Retrieve the Master Key
   */
  async getMasterKey(): Promise<Uint8Array | null> {
    const value = await this.storage.get(STORAGE_KEYS.MASTER_KEY);
    if (!value) return null;
    return fromBase64(value);
  }

  /**
   * Check if Master Key exists
   */
  async hasMasterKey(): Promise<boolean> {
    return this.storage.has(STORAGE_KEYS.MASTER_KEY);
  }

  /**
   * Delete the Master Key
   */
  async deleteMasterKey(): Promise<boolean> {
    return this.storage.delete(STORAGE_KEYS.MASTER_KEY);
  }

  /**
   * Store the device ID
   */
  async setDeviceId(deviceId: string): Promise<void> {
    await this.storage.set(STORAGE_KEYS.DEVICE_ID, deviceId);
  }

  /**
   * Retrieve the device ID
   */
  async getDeviceId(): Promise<string | null> {
    return this.storage.get(STORAGE_KEYS.DEVICE_ID);
  }

  /**
   * Store the device private key
   */
  async setDevicePrivateKey(privateKey: Uint8Array): Promise<void> {
    await this.storage.set(
      STORAGE_KEYS.DEVICE_PRIVATE_KEY,
      toBase64(privateKey)
    );
  }

  /**
   * Retrieve the device private key
   */
  async getDevicePrivateKey(): Promise<Uint8Array | null> {
    const value = await this.storage.get(STORAGE_KEYS.DEVICE_PRIVATE_KEY);
    if (!value) return null;
    return fromBase64(value);
  }

  /**
   * Store the API key (Unkey token)
   */
  async setApiKey(apiKey: string): Promise<void> {
    await this.storage.set(STORAGE_KEYS.API_KEY, apiKey);
  }

  /**
   * Retrieve the API key
   */
  async getApiKey(): Promise<string | null> {
    return this.storage.get(STORAGE_KEYS.API_KEY);
  }

  /**
   * Check if API key exists
   */
  async hasApiKey(): Promise<boolean> {
    return this.storage.has(STORAGE_KEYS.API_KEY);
  }

  /**
   * Delete the API key
   */
  async deleteApiKey(): Promise<boolean> {
    return this.storage.delete(STORAGE_KEYS.API_KEY);
  }

  /**
   * Store the device fingerprint
   */
  async setDeviceFingerprint(fingerprint: string): Promise<void> {
    await this.storage.set(STORAGE_KEYS.DEVICE_FINGERPRINT, fingerprint);
  }

  /**
   * Retrieve the device fingerprint
   */
  async getDeviceFingerprint(): Promise<string | null> {
    return this.storage.get(STORAGE_KEYS.DEVICE_FINGERPRINT);
  }

  /**
   * Check if the device is linked (has required credentials)
   */
  async isDeviceLinked(): Promise<boolean> {
    const hasApiKey = await this.hasApiKey();
    const deviceId = await this.getDeviceId();
    return hasApiKey && deviceId !== null;
  }

  /**
   * Check if the device is paired (has Master Key)
   */
  async isDevicePaired(): Promise<boolean> {
    return this.hasMasterKey();
  }

  /**
   * Clear all stored secrets (for unlinking)
   */
  async clearAll(): Promise<void> {
    await Promise.all([
      this.storage.delete(STORAGE_KEYS.MASTER_KEY),
      this.storage.delete(STORAGE_KEYS.DEVICE_ID),
      this.storage.delete(STORAGE_KEYS.DEVICE_PRIVATE_KEY),
      this.storage.delete(STORAGE_KEYS.API_KEY),
      this.storage.delete(STORAGE_KEYS.DEVICE_FINGERPRINT),
    ]);
  }
}

/**
 * Create a secrets manager with the given storage backend
 */
export function createSecretsManager(storage: SecureStorage): SecretsManager {
  return new SecretsManager(storage);
}
