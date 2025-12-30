import { z } from "zod";
import { AuthMessageSchema } from "./auth.js";

/**
 * SUBSCRIBE command - join a session
 */
export const SubscribeCommandSchema = z.object({
  type: z.literal("SUBSCRIBE"),
  sessionId: z.string().uuid(),
});

export type SubscribeCommand = z.infer<typeof SubscribeCommandSchema>;

/**
 * UNSUBSCRIBE command - leave a session
 */
export const UnsubscribeCommandSchema = z.object({
  type: z.literal("UNSUBSCRIBE"),
  sessionId: z.string().uuid(),
});

export type UnsubscribeCommand = z.infer<typeof UnsubscribeCommandSchema>;

/**
 * HEARTBEAT command - keep connection alive
 */
export const HeartbeatCommandSchema = z.object({
  type: z.literal("HEARTBEAT"),
});

export type HeartbeatCommand = z.infer<typeof HeartbeatCommandSchema>;

/**
 * All commands the relay understands (not encrypted)
 */
export const RelayCommandSchema = z.discriminatedUnion("type", [
  AuthMessageSchema,
  SubscribeCommandSchema,
  UnsubscribeCommandSchema,
  HeartbeatCommandSchema,
]);

export type RelayCommand = z.infer<typeof RelayCommandSchema>;

/**
 * Parse a relay command from unknown data
 */
export function parseRelayCommand(
  data: unknown
):
  | { success: true; data: RelayCommand }
  | { success: false; error: z.ZodError } {
  const result = RelayCommandSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error };
}
