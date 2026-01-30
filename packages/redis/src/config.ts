import { z } from "zod";

/**
 * Configuration schema for Upstash Redis REST API connection.
 * Validates required environment variables.
 */
export const RedisConfigSchema = z.object({
  /** Upstash Redis REST API URL */
  UPSTASH_REDIS_REST_URL: z
    .string()
    .url("UPSTASH_REDIS_REST_URL must be a valid URL"),
  /** Upstash Redis REST API token */
  UPSTASH_REDIS_REST_TOKEN: z
    .string()
    .min(1, "UPSTASH_REDIS_REST_TOKEN is required"),
});

/** Inferred type from RedisConfigSchema */
export type RedisConfig = z.infer<typeof RedisConfigSchema>;

/**
 * Configuration schema for Redis TCP connection using ioredis.
 * Validates required environment variables for native Redis protocol.
 */
export const RedisTCPConfigSchema = z.object({
  /** Redis host (e.g., 'redis.example.com' or 'xxx.upstash.io') */
  REDIS_HOST: z.string().min(1, "REDIS_HOST is required"),
  /** Redis port (default: 6379 or 6380 for TLS) */
  REDIS_PORT: z.string().transform((val) => Number.parseInt(val, 10)),
  /** Redis password/auth token */
  REDIS_PASSWORD: z.string().min(1, "REDIS_PASSWORD is required"),
  /** Enable TLS/SSL connection (true for Upstash) */
  REDIS_TLS: z
    .string()
    .optional()
    .transform((val) => val === "true" || val === "1"),
});

/** Inferred type from RedisTCPConfigSchema */
export type RedisTCPConfig = z.infer<typeof RedisTCPConfigSchema>;
