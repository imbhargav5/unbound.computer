import { fromBase64, toBase64 } from "@unbound/crypto";
import {
  createKeychainStorage,
  createSecretsManager,
  type SecretsManager,
} from "@unbound/storage";
import { KEYCHAIN_SERVICE, paths } from "../config.js";
import { ensureDir, readJsonFile, writeJsonFile } from "../utils/index.js";

/**
 * Local config file structure (non-sensitive data)
 */
interface LocalConfig {
  deviceId?: string;
  deviceName?: string;
  userId?: string;
  apiUrl?: string;
  relayUrl?: string;
  linkedAt?: string;
}

/**
 * Credential storage for CLI
 * - Secrets stored in OS keychain via @unbound/storage
 * - Non-sensitive config in ~/.unbound/config.json
 */
class CredentialStorage {
  private secrets: SecretsManager | null = null;
  private localConfig: LocalConfig | null = null;

  /**
   * Initialize storage (ensure directories exist)
   */
  async init(): Promise<void> {
    await ensureDir(paths.configDir);
    await ensureDir(paths.logsDir);

    // Initialize keychain storage
    const storage = createKeychainStorage(KEYCHAIN_SERVICE);
    this.secrets = createSecretsManager(storage);

    await this.loadLocalConfig();
  }

  private getSecrets(): SecretsManager {
    if (!this.secrets) {
      throw new Error("CredentialStorage not initialized. Call init() first.");
    }
    return this.secrets;
  }

  /**
   * Load local config file
   */
  private async loadLocalConfig(): Promise<void> {
    this.localConfig = await readJsonFile<LocalConfig>(paths.configFile);
    if (!this.localConfig) {
      this.localConfig = {};
    }
  }

  /**
   * Save local config file
   */
  private async saveLocalConfig(): Promise<void> {
    if (this.localConfig) {
      await writeJsonFile(paths.configFile, this.localConfig);
    }
  }

  /**
   * Check if device is linked
   */
  async isLinked(): Promise<boolean> {
    const apiKey = await this.getApiKey();
    const deviceId = await this.getDeviceId();
    return !!apiKey && !!deviceId;
  }

  /**
   * Store API key in keychain
   */
  async setApiKey(apiKey: string): Promise<void> {
    await this.getSecrets().setApiKey(apiKey);
  }

  /**
   * Get API key from keychain
   */
  async getApiKey(): Promise<string | null> {
    return this.getSecrets().getApiKey();
  }

  /**
   * Store device ID
   */
  async setDeviceId(deviceId: string): Promise<void> {
    await this.getSecrets().setDeviceId(deviceId);
    if (this.localConfig) {
      this.localConfig.deviceId = deviceId;
      await this.saveLocalConfig();
    }
  }

  /**
   * Get device ID
   */
  async getDeviceId(): Promise<string | null> {
    return this.getSecrets().getDeviceId();
  }

  /**
   * Store device name
   */
  async setDeviceName(name: string): Promise<void> {
    if (this.localConfig) {
      this.localConfig.deviceName = name;
      await this.saveLocalConfig();
    }
  }

  /**
   * Get device name
   */
  getDeviceName(): string | null {
    return this.localConfig?.deviceName ?? null;
  }

  /**
   * Store user ID
   */
  async setUserId(userId: string): Promise<void> {
    if (this.localConfig) {
      this.localConfig.userId = userId;
      await this.saveLocalConfig();
    }
  }

  /**
   * Get user ID
   */
  getUserId(): string | null {
    return this.localConfig?.userId ?? null;
  }

  /**
   * Store master key in keychain (as base64 string)
   */
  async setMasterKey(masterKey: Uint8Array): Promise<void> {
    await this.getSecrets().setMasterKey(masterKey);
  }

  /**
   * Get master key from keychain
   */
  async getMasterKey(): Promise<Uint8Array | null> {
    return this.getSecrets().getMasterKey();
  }

  /**
   * Check if master key exists in keychain
   */
  async hasMasterKey(): Promise<boolean> {
    return this.getSecrets().hasMasterKey();
  }

  /**
   * Store device private key in keychain (as base64 string)
   */
  async setDevicePrivateKey(privateKey: Uint8Array): Promise<void> {
    await this.getSecrets().setDevicePrivateKey(privateKey);
  }

  /**
   * Get device private key from keychain
   */
  async getDevicePrivateKey(): Promise<Uint8Array | null> {
    return this.getSecrets().getDevicePrivateKey();
  }

  /**
   * Store device private key as base64 string (for compatibility)
   */
  async setDevicePrivateKeyBase64(privateKeyBase64: string): Promise<void> {
    const privateKey = fromBase64(privateKeyBase64);
    await this.getSecrets().setDevicePrivateKey(privateKey);
  }

  /**
   * Get device private key as base64 string (for compatibility)
   */
  async getDevicePrivateKeyBase64(): Promise<string | null> {
    const privateKey = await this.getSecrets().getDevicePrivateKey();
    if (!privateKey) return null;
    return toBase64(privateKey);
  }

  /**
   * Store link timestamp
   */
  async setLinkedAt(date: Date): Promise<void> {
    if (this.localConfig) {
      this.localConfig.linkedAt = date.toISOString();
      await this.saveLocalConfig();
    }
  }

  /**
   * Get link timestamp
   */
  getLinkedAt(): Date | null {
    if (this.localConfig?.linkedAt) {
      return new Date(this.localConfig.linkedAt);
    }
    return null;
  }

  /**
   * Clear all credentials and config
   */
  async clear(): Promise<void> {
    await this.getSecrets().clearAll();

    this.localConfig = {};
    await this.saveLocalConfig();
  }

  /**
   * Get local config (non-sensitive)
   */
  getConfig(): LocalConfig {
    return this.localConfig ?? {};
  }
}

// Singleton instance
export const credentials = new CredentialStorage();
