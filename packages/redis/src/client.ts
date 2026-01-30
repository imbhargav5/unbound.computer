import { Redis } from "@upstash/redis";
import { type RedisConfig, RedisConfigSchema } from "./config.js";

let client: Redis | null = null;

/**
 * Creates and initializes the Redis client singleton.
 * Validates configuration using Zod schema before creating the client.
 *
 * @param env - Environment variables containing UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN
 * @returns The initialized Redis client
 * @throws {z.ZodError} If configuration validation fails
 *
 * @example
 * ```typescript
 * const redis = createRedisClient(process.env);
 * ```
 */
export function createRedisClient(
  env: Record<string, string | undefined>
): Redis {
  if (client) {
    return client;
  }

  const config: RedisConfig = RedisConfigSchema.parse({
    UPSTASH_REDIS_REST_URL: env.UPSTASH_REDIS_REST_URL,
    UPSTASH_REDIS_REST_TOKEN: env.UPSTASH_REDIS_REST_TOKEN,
  });

  client = new Redis({
    url: config.UPSTASH_REDIS_REST_URL,
    token: config.UPSTASH_REDIS_REST_TOKEN,
  });

  return client;
}

/**
 * Gets the existing Redis client singleton.
 *
 * @returns The Redis client
 * @throws {Error} If the client has not been initialized via createRedisClient
 *
 * @example
 * ```typescript
 * const redis = getRedisClient();
 * await redis.get("key");
 * ```
 */
export function getRedisClient(): Redis {
  if (!client) {
    throw new Error(
      "Redis client not initialized. Call createRedisClient(env) first."
    );
  }
  return client;
}

/**
 * Resets the Redis client singleton.
 * Useful for testing or when switching connections.
 */
export function resetRedisClient(): void {
  client = null;
}
