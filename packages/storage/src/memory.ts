import type { SecureStorage } from "./types.js";

/**
 * In-memory storage for testing and development
 * NOT for production use - values are not persisted
 */
export class MemoryStorage implements SecureStorage {
  private store: Map<string, string>;

  constructor() {
    this.store = new Map();
  }

  async set(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }

  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }

  async delete(key: string): Promise<boolean> {
    return this.store.delete(key);
  }

  async has(key: string): Promise<boolean> {
    return this.store.has(key);
  }

  /**
   * Clear all stored values
   */
  clear(): void {
    this.store.clear();
  }
}

/**
 * Create an in-memory storage instance
 */
export function createMemoryStorage(): SecureStorage {
  return new MemoryStorage();
}
