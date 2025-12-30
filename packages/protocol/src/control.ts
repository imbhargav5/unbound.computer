import { z } from "zod";

/**
 * Typing indicator
 */
export const TypingSchema = z.object({
  action: z.literal("TYPING"),
  isTyping: z.boolean(),
});

/**
 * Device is ready
 */
export const ReadySchema = z.object({
  action: z.literal("READY"),
});

/**
 * Device is waiting
 */
export const WaitingSchema = z.object({
  action: z.literal("WAITING"),
  reason: z.string().optional(),
});

/**
 * Error message
 */
export const ErrorSchema = z.object({
  action: z.literal("ERROR"),
  code: z.string(),
  message: z.string(),
});

/**
 * Acknowledgement
 */
export const AckSchema = z.object({
  action: z.literal("ACK"),
  messageId: z.string().uuid(),
});

/**
 * Heartbeat
 */
export const HeartbeatSchema = z.object({
  action: z.literal("HEARTBEAT"),
});

/**
 * Union of all control messages
 */
export const ControlMessageSchema = z.discriminatedUnion("action", [
  TypingSchema,
  ReadySchema,
  WaitingSchema,
  ErrorSchema,
  AckSchema,
  HeartbeatSchema,
]);

export type Typing = z.infer<typeof TypingSchema>;
export type Ready = z.infer<typeof ReadySchema>;
export type Waiting = z.infer<typeof WaitingSchema>;
export type Error = z.infer<typeof ErrorSchema>;
export type Ack = z.infer<typeof AckSchema>;
export type Heartbeat = z.infer<typeof HeartbeatSchema>;
export type ControlMessage = z.infer<typeof ControlMessageSchema>;

/**
 * Validate a control message
 */
export function validateControlMessage(data: unknown): ControlMessage {
  return ControlMessageSchema.parse(data);
}

/**
 * Safe parse a control message
 */
export function parseControlMessage(
  data: unknown
):
  | { success: true; data: ControlMessage }
  | { success: false; error: z.ZodError } {
  const result = ControlMessageSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error };
}
