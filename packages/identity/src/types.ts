import { z } from "zod";

/**
 * Device types
 */
export const DeviceTypeSchema = z.enum([
  "mac",
  "linux",
  "windows",
  "ios",
  "android",
]);
export type DeviceType = z.infer<typeof DeviceTypeSchema>;

/**
 * Device identity
 */
export interface DeviceIdentity {
  id: string;
  name: string;
  type: DeviceType;
  fingerprint: string;
  publicKey: Uint8Array;
  createdAt: Date;
}

/**
 * Session identity
 */
export interface SessionIdentity {
  id: string;
  deviceId: string;
  repositoryId?: string;
  createdAt: Date;
  expiresAt?: Date;
}

/**
 * Serializable device info for storage/transport
 */
export const DeviceInfoSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  type: DeviceTypeSchema,
  fingerprint: z.string(),
  publicKey: z.string(), // Base64-encoded
  createdAt: z.string().datetime(),
});

export type DeviceInfo = z.infer<typeof DeviceInfoSchema>;

/**
 * Serializable session info for storage/transport
 */
export const SessionInfoSchema = z.object({
  id: z.string().uuid(),
  deviceId: z.string().uuid(),
  repositoryId: z.string().uuid().optional(),
  createdAt: z.string().datetime(),
  expiresAt: z.string().datetime().optional(),
});

export type SessionInfo = z.infer<typeof SessionInfoSchema>;
