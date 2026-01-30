import type { WebSessionStorage } from "./types.js";

const STORAGE_PREFIX = "unbound_web_session_";

/**
 * Session storage adapter (clears on tab close)
 * This is the recommended storage for web sessions
 */
export class BrowserSessionStorage implements WebSessionStorage {
  set(key: string, value: string): void {
    if (typeof sessionStorage !== "undefined") {
      sessionStorage.setItem(STORAGE_PREFIX + key, value);
    }
  }

  get(key: string): string | null {
    if (typeof sessionStorage !== "undefined") {
      return sessionStorage.getItem(STORAGE_PREFIX + key);
    }
    return null;
  }

  remove(key: string): void {
    if (typeof sessionStorage !== "undefined") {
      sessionStorage.removeItem(STORAGE_PREFIX + key);
    }
  }

  clear(): void {
    if (typeof sessionStorage !== "undefined") {
      const keysToRemove: string[] = [];
      for (let i = 0; i < sessionStorage.length; i++) {
        const key = sessionStorage.key(i);
        if (key?.startsWith(STORAGE_PREFIX)) {
          keysToRemove.push(key);
        }
      }
      for (const key of keysToRemove) {
        sessionStorage.removeItem(key);
      }
    }
  }
}

/**
 * In-memory storage for testing or SSR
 */
export class MemoryStorage implements WebSessionStorage {
  private store = new Map<string, string>();

  set(key: string, value: string): void {
    this.store.set(STORAGE_PREFIX + key, value);
  }

  get(key: string): string | null {
    return this.store.get(STORAGE_PREFIX + key) ?? null;
  }

  remove(key: string): void {
    this.store.delete(STORAGE_PREFIX + key);
  }

  clear(): void {
    const keysToRemove: string[] = [];
    for (const key of this.store.keys()) {
      if (key.startsWith(STORAGE_PREFIX)) {
        keysToRemove.push(key);
      }
    }
    for (const key of keysToRemove) {
      this.store.delete(key);
    }
  }
}

/**
 * Storage keys
 */
export const STORAGE_KEYS = {
  SESSION_ID: "session_id",
  SESSION_TOKEN: "session_token",
  SESSION_KEY: "session_key",
  PRIVATE_KEY: "private_key",
  EXPIRES_AT: "expires_at",
} as const;
