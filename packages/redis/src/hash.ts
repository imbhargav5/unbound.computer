import { getRedisClient } from "./client.js";

/**
 * Gets a field value from a hash.
 *
 * @param key - The hash key
 * @param field - The field name
 * @returns The field value or null if not found
 *
 * @example
 * ```typescript
 * const name = await hget<string>("user:123", "name");
 * ```
 */
export async function hget<T>(key: string, field: string): Promise<T | null> {
  const client = getRedisClient();
  return client.hget<T>(key, field);
}

/**
 * Sets a field value in a hash.
 *
 * @param key - The hash key
 * @param field - The field name
 * @param value - The value to set
 *
 * @example
 * ```typescript
 * await hset("user:123", "name", "John");
 * ```
 */
export async function hset(
  key: string,
  field: string,
  value: unknown
): Promise<void> {
  const client = getRedisClient();
  await client.hset(key, { [field]: value });
}

/**
 * Deletes one or more fields from a hash.
 *
 * @param key - The hash key
 * @param fields - The field names to delete
 * @returns The number of fields deleted
 *
 * @example
 * ```typescript
 * const count = await hdel("user:123", "field1", "field2");
 * ```
 */
export async function hdel(key: string, ...fields: string[]): Promise<number> {
  const client = getRedisClient();
  return client.hdel(key, ...fields);
}

/**
 * Gets all fields and values from a hash.
 *
 * @param key - The hash key
 * @returns Object containing all field-value pairs, or null if key doesn't exist
 *
 * @example
 * ```typescript
 * const user = await hgetall<string>("user:123");
 * // { name: "John", email: "john@example.com" }
 * ```
 */
export async function hgetall<T>(
  key: string
): Promise<Record<string, T> | null> {
  const client = getRedisClient();
  const result = await client.hgetall<Record<string, T>>(key);
  if (!result || Object.keys(result).length === 0) {
    return null;
  }
  return result;
}

/**
 * Sets multiple fields in a hash.
 *
 * @param key - The hash key
 * @param data - Object containing field-value pairs
 *
 * @example
 * ```typescript
 * await hmset("user:123", { name: "John", email: "john@example.com" });
 * ```
 */
export async function hmset(
  key: string,
  data: Record<string, unknown>
): Promise<void> {
  const client = getRedisClient();
  await client.hset(key, data);
}
