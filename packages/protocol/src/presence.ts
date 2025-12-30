import { z } from "zod";

/**
 * Device presence status
 */
export const PresenceStatusSchema = z.enum(["online", "offline", "away"]);

/**
 * Presence message
 */
export const PresenceMessageSchema = z.object({
  status: PresenceStatusSchema,
  deviceId: z.string().uuid(),
  deviceName: z.string().optional(),
  lastSeenAt: z.number().optional(),
});

export type PresenceStatus = z.infer<typeof PresenceStatusSchema>;
export type PresenceMessage = z.infer<typeof PresenceMessageSchema>;

/**
 * Validate a presence message
 */
export function validatePresenceMessage(data: unknown): PresenceMessage {
  return PresenceMessageSchema.parse(data);
}

/**
 * Safe parse a presence message
 */
export function parsePresenceMessage(
  data: unknown
):
  | { success: true; data: PresenceMessage }
  | { success: false; error: z.ZodError } {
  const result = PresenceMessageSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error };
}

/**
 * Create a presence message
 */
export function createPresenceMessage(
  status: PresenceStatus,
  deviceId: string,
  deviceName?: string
): PresenceMessage {
  return {
    status,
    deviceId,
    deviceName,
    lastSeenAt: status === "online" ? Date.now() : undefined,
  };
}
