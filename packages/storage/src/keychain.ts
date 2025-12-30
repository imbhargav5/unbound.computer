import type { SecureStorage } from "./types.js";

/**
 * Service name for keychain storage
 */
const SERVICE_NAME = "com.unbound.cli";

/**
 * Keychain-based secure storage using the OS keyring
 * Uses the `keytar` library for cross-platform keychain access
 *
 * - macOS: Keychain
 * - Linux: libsecret / Secret Service API
 * - Windows: Credential Vault
 */
export class KeychainStorage implements SecureStorage {
  private keytar: typeof import("keytar") | null = null;
  private serviceName: string;

  constructor(serviceName = SERVICE_NAME) {
    this.serviceName = serviceName;
  }

  private async getKeytar(): Promise<typeof import("keytar")> {
    if (!this.keytar) {
      // Dynamic import to avoid issues in environments without keytar
      this.keytar = await import("keytar");
    }
    return this.keytar;
  }

  async set(key: string, value: string): Promise<void> {
    const keytar = await this.getKeytar();
    await keytar.setPassword(this.serviceName, key, value);
  }

  async get(key: string): Promise<string | null> {
    const keytar = await this.getKeytar();
    return keytar.getPassword(this.serviceName, key);
  }

  async delete(key: string): Promise<boolean> {
    const keytar = await this.getKeytar();
    return keytar.deletePassword(this.serviceName, key);
  }

  async has(key: string): Promise<boolean> {
    const value = await this.get(key);
    return value !== null;
  }
}

/**
 * Create a keychain storage instance
 */
export function createKeychainStorage(serviceName?: string): SecureStorage {
  return new KeychainStorage(serviceName);
}
