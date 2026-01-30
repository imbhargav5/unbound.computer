import { z } from "zod";

/**
 * Message types that can be sent through the relay
 */
export const MessageTypeSchema = z.enum([
  "message",
  "presence",
  "pairing",
  "control",
  "session",
]);

/**
 * Relay envelope - the outer wrapper for all messages
 * The relay only inspects these fields, never the payload
 */
export const RelayEnvelopeSchema = z.object({
  type: MessageTypeSchema,
  sessionId: z.string().uuid(),
  senderId: z.string().uuid(),
  timestamp: z.number(),
  payload: z.string(), // Base64-encoded encrypted payload
});

export type RelayEnvelope = z.infer<typeof RelayEnvelopeSchema>;

/**
 * Create a relay envelope
 */
export function createEnvelope(
  type: z.infer<typeof MessageTypeSchema>,
  sessionId: string,
  senderId: string,
  payload: string
): RelayEnvelope {
  return {
    type,
    sessionId,
    senderId,
    timestamp: Date.now(),
    payload,
  };
}

/**
 * Validate a relay envelope
 */
export function validateEnvelope(data: unknown): RelayEnvelope {
  return RelayEnvelopeSchema.parse(data);
}

/**
 * Safe parse a relay envelope
 */
export function parseEnvelope(
  data: unknown
):
  | { success: true; data: RelayEnvelope }
  | { success: false; error: z.ZodError } {
  const result = RelayEnvelopeSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error };
}
