import { fromBase64, toBase64 } from "@unbound/crypto";
import type { SecureStorage, TrustedDevice } from "./types.js";
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
   * @deprecated Use hasTrustedDevices() instead
   */
  async isDevicePaired(): Promise<boolean> {
    return this.hasMasterKey();
  }

  // ==========================================
  // Trusted Devices Management (Device-Rooted Trust)
  // ==========================================

  /**
   * Get all trusted devices
   */
  async getTrustedDevices(): Promise<TrustedDevice[]> {
    const value = await this.storage.get(STORAGE_KEYS.TRUSTED_DEVICES);
    if (!value) return [];
    try {
      return JSON.parse(value) as TrustedDevice[];
    } catch {
      return [];
    }
  }

  /**
   * Add a trusted device
   */
  async addTrustedDevice(device: TrustedDevice): Promise<void> {
    const devices = await this.getTrustedDevices();
    // Remove existing entry for this device if present
    const filtered = devices.filter((d) => d.deviceId !== device.deviceId);
    filtered.push(device);
    await this.storage.set(
      STORAGE_KEYS.TRUSTED_DEVICES,
      JSON.stringify(filtered)
    );
  }

  /**
   * Remove a trusted device
   */
  async removeTrustedDevice(deviceId: string): Promise<boolean> {
    const devices = await this.getTrustedDevices();
    const filtered = devices.filter((d) => d.deviceId !== deviceId);
    if (filtered.length === devices.length) {
      return false; // Device not found
    }
    await this.storage.set(
      STORAGE_KEYS.TRUSTED_DEVICES,
      JSON.stringify(filtered)
    );
    return true;
  }

  /**
   * Check if a device is trusted
   */
  async isTrustedDevice(deviceId: string): Promise<boolean> {
    const devices = await this.getTrustedDevices();
    const device = devices.find((d) => d.deviceId === deviceId);
    if (!device) return false;
    // Check expiration
    if (device.expiresAt && new Date(device.expiresAt) < new Date()) {
      return false;
    }
    return true;
  }

  /**
   * Get a specific trusted device by ID
   */
  async getTrustedDevice(deviceId: string): Promise<TrustedDevice | null> {
    const devices = await this.getTrustedDevices();
    return devices.find((d) => d.deviceId === deviceId) ?? null;
  }

  /**
   * Check if any trusted devices exist
   */
  async hasTrustedDevices(): Promise<boolean> {
    const devices = await this.getTrustedDevices();
    return devices.length > 0;
  }

  /**
   * Get the trust root device (if present)
   */
  async getTrustRoot(): Promise<TrustedDevice | null> {
    const devices = await this.getTrustedDevices();
    return devices.find((d) => d.role === "trust_root") ?? null;
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
      this.storage.delete(STORAGE_KEYS.TRUSTED_DEVICES),
    ]);
  }
}

/**
 * Create a secrets manager with the given storage backend
 */
export function createSecretsManager(storage: SecureStorage): SecretsManager {
  return new SecretsManager(storage);
}
