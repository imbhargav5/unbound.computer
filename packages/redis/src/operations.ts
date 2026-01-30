import { getRedisClient } from "./client.js";

/**
 * Options for the set operation.
 */
export interface SetOptions {
  /** Time-to-live in seconds */
  ex?: number;
}

/**
 * Gets a value by key.
 *
 * @param key - The key to retrieve
 * @returns The value or null if not found
 *
 * @example
 * ```typescript
 * const user = await get<User>("user:123");
 * ```
 */
export async function get<T>(key: string): Promise<T | null> {
  const client = getRedisClient();
  return client.get<T>(key);
}

/**
 * Sets a value with an optional TTL.
 *
 * @param key - The key to set
 * @param value - The value to store
 * @param options - Optional settings including TTL
 *
 * @example
 * ```typescript
 * await set("user:123", { name: "John" }, { ex: 3600 });
 * ```
 */
export async function set(
  key: string,
  value: unknown,
  options?: SetOptions
): Promise<void> {
  const client = getRedisClient();
  if (options?.ex) {
    await client.set(key, value, { ex: options.ex });
  } else {
    await client.set(key, value);
  }
}

/**
 * Deletes one or more keys.
 *
 * @param keys - The keys to delete
 * @returns The number of keys deleted
 *
 * @example
 * ```typescript
 * const count = await del("key1", "key2");
 * ```
 */
export async function del(...keys: string[]): Promise<number> {
  const client = getRedisClient();
  return client.del(...keys);
}

/**
 * Gets multiple values by keys.
 *
 * @param keys - The keys to retrieve
 * @returns Array of values (null for missing keys)
 *
 * @example
 * ```typescript
 * const [user1, user2] = await mget<User>("user:1", "user:2");
 * ```
 */
export async function mget<T>(...keys: string[]): Promise<(T | null)[]> {
  const client = getRedisClient();
  return client.mget<(T | null)[]>(...keys);
}

/**
 * Sets multiple key-value pairs.
 *
 * @param entries - Object containing key-value pairs
 *
 * @example
 * ```typescript
 * await mset({ "key1": "value1", "key2": "value2" });
 * ```
 */
export async function mset(entries: Record<string, unknown>): Promise<void> {
  const client = getRedisClient();
  await client.mset(entries);
}

/**
 * Sets expiration time on an existing key.
 *
 * @param key - The key to set expiration on
 * @param seconds - TTL in seconds
 * @returns true if timeout was set, false if key doesn't exist
 *
 * @example
 * ```typescript
 * const success = await expire("session:abc", 3600);
 * ```
 */
export async function expire(key: string, seconds: number): Promise<boolean> {
  const client = getRedisClient();
  const result = await client.expire(key, seconds);
  return result === 1;
}

/**
 * Gets the remaining TTL of a key.
 *
 * @param key - The key to check
 * @returns TTL in seconds, -1 if no expiry, -2 if key doesn't exist
 *
 * @example
 * ```typescript
 * const remaining = await ttl("session:abc");
 * ```
 */
export async function ttl(key: string): Promise<number> {
  const client = getRedisClient();
  return client.ttl(key);
}

/**
 * Checks if one or more keys exist.
 *
 * @param keys - The keys to check
 * @returns The number of keys that exist
 *
 * @example
 * ```typescript
 * const count = await exists("key1", "key2");
 * ```
 */
export async function exists(...keys: string[]): Promise<number> {
  const client = getRedisClient();
  return client.exists(...keys);
}
