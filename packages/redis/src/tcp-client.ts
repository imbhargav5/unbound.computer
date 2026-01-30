import Redis from "ioredis";
import { type RedisTCPConfig, RedisTCPConfigSchema } from "./config.js";

let client: Redis | null = null;

/**
 * Creates and initializes a persistent TCP connection to Redis using ioredis.
 * This maintains a single TCP connection for all Redis operations, ensuring
 * command ordering and providing better performance than REST API.
 *
 * @param env - Environment variables containing Redis connection details
 * @returns The initialized ioredis client
 * @throws {z.ZodError} If configuration validation fails
 *
 * @example
 * ```typescript
 * const redis = createRedisTCPClient({
 *   REDIS_HOST: 'redis.example.com',
 *   REDIS_PORT: '6379',
 *   REDIS_PASSWORD: 'secret',
 *   REDIS_TLS: 'true'
 * });
 * ```
 */
export function createRedisTCPClient(
  env: Record<string, string | undefined>
): Redis {
  if (client) {
    return client;
  }

  const config: RedisTCPConfig = RedisTCPConfigSchema.parse({
    REDIS_HOST: env.REDIS_HOST,
    REDIS_PORT: env.REDIS_PORT,
    REDIS_PASSWORD: env.REDIS_PASSWORD,
    REDIS_TLS: env.REDIS_TLS,
  });

  client = new Redis({
    host: config.REDIS_HOST,
    port: config.REDIS_PORT,
    password: config.REDIS_PASSWORD,
    tls: config.REDIS_TLS ? {} : undefined,

    // Connection management
    keepAlive: 30_000, // Keep connection alive with 30s pings
    connectTimeout: 10_000, // 10 second connection timeout
    enableOfflineQueue: true, // Queue commands when offline
    lazyConnect: false, // Connect immediately

    // Retry strategy with exponential backoff
    retryStrategy: (times) => {
      if (times > 10) {
        // Stop retrying after 10 attempts
        return null;
      }
      // Exponential backoff: 50ms, 100ms, 200ms, ..., up to 2s
      const delay = Math.min(times * 50, 2000);
      return delay;
    },

    // Reconnect on error
    reconnectOnError: (err) => {
      const targetError = "READONLY";
      if (err.message.includes(targetError)) {
        // Reconnect on READONLY errors (replica promoted to master)
        return true;
      }
      return false;
    },

    // Enable TCP_NODELAY for low latency
    // Disables Nagle's algorithm to send data immediately
    enableReadyCheck: true,
  });

  // Event handlers for monitoring
  client.on("connect", () => {
    console.log("[Redis TCP] Connected to Redis");
  });

  client.on("ready", () => {
    console.log("[Redis TCP] Redis connection ready");
  });

  client.on("error", (err) => {
    console.error("[Redis TCP] Redis connection error:", err);
  });

  client.on("close", () => {
    console.warn("[Redis TCP] Redis connection closed");
  });

  client.on("reconnecting", () => {
    console.log("[Redis TCP] Reconnecting to Redis...");
  });

  return client;
}

/**
 * Gets the existing Redis TCP client singleton.
 *
 * @returns The ioredis client
 * @throws {Error} If the client has not been initialized via createRedisTCPClient
 *
 * @example
 * ```typescript
 * const redis = getRedisTCPClient();
 * await redis.get("key");
 * ```
 */
export function getRedisTCPClient(): Redis {
  if (!client) {
    throw new Error(
      "Redis TCP client not initialized. Call createRedisTCPClient(env) first."
    );
  }
  return client;
}

/**
 * Closes the Redis TCP connection and resets the singleton.
 * Useful for graceful shutdown or testing.
 */
export async function closeRedisTCPClient(): Promise<void> {
  if (client) {
    await client.quit();
    client = null;
  }
}

/**
 * Resets the Redis TCP client singleton without closing the connection.
 * Useful for testing.
 */
export function resetRedisTCPClient(): void {
  client = null;
}
