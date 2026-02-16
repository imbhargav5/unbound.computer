import { z } from "zod";

const uuidSchema = z.string().uuid();

export const presenceStatusSchema = z.enum(["online", "offline"]);
export type PresenceStatus = z.infer<typeof presenceStatusSchema>;

export const presenceBaseSchema = z.object({
  schema_version: z.literal(1),
  user_id: uuidSchema,
  device_id: uuidSchema,
  status: presenceStatusSchema,
  source: z.string().min(1),
  sent_at_ms: z.number().int().nonnegative(),
  seq: z.number().int().nonnegative(),
  ttl_ms: z.number().int().positive(),
});
export type PresenceStreamPayload = z.infer<typeof presenceBaseSchema>;

export const presenceStorageSchema = presenceBaseSchema.extend({
  last_heartbeat_ms: z.number().int().nonnegative(),
  last_offline_ms: z.number().int().nonnegative().nullable(),
  updated_at_ms: z.number().int().nonnegative(),
});
export type PresenceStorageRecord = z.infer<typeof presenceStorageSchema>;

export const presenceTokenResponseSchema = z.object({
  token: z.string().min(1),
  expires_at_ms: z.number().int().nonnegative(),
  user_id: uuidSchema,
  device_id: uuidSchema,
  scope: z.array(z.string().min(1)),
});
export type PresenceTokenResponse = z.infer<typeof presenceTokenResponseSchema>;

export const presenceErrorCodeSchema = z.enum([
  "unauthorized",
  "forbidden",
  "rate_limited",
  "unavailable",
  "invalid_payload",
]);
export type PresenceErrorCode = z.infer<typeof presenceErrorCodeSchema>;

export const presenceErrorSchema = z.object({
  error: presenceErrorCodeSchema,
  details: z.string().optional(),
  statusCode: z.number().int().optional(),
});
export type PresenceError = z.infer<typeof presenceErrorSchema>;

export const presenceScopeDefault = ["presence:read", "presence:write"] as const;

export function normalizePresenceIdentifier(value: string): string {
  return value.trim().toLowerCase();
}
