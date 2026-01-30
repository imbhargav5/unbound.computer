import { z } from "zod";
import { UlidSchema } from "./relay-envelope.js";

/**
 * Role for a session message
 */
export const MessageRoleSchema = z.enum(["user", "assistant", "system"]);
export type MessageRole = z.infer<typeof MessageRoleSchema>;

/**
 * Session message with encrypted content
 * Used for relay ingestion - content is encrypted, role is plaintext for routing
 */
export const SessionMessageSchema = z.object({
  // Identifiers
  eventId: UlidSchema,
  sessionId: z.string().min(1),
  messageId: UlidSchema, // Reference to the stored message

  // Unencrypted metadata (for routing and display)
  role: MessageRoleSchema,
  sequenceNumber: z.number().int().nonnegative(),
  createdAt: z.number(), // Unix milliseconds

  // Encrypted content (eventType is inside the encrypted payload)
  contentEncrypted: z.string(), // Base64 encoded
  contentNonce: z.string(), // Base64 encoded

  // Optional: sessionEventType for routing (derived from encrypted content on client)
  sessionEventType: z.enum([
    "REMOTE_COMMAND",
    "EXECUTOR_UPDATE",
    "LOCAL_EXECUTION_COMMAND",
  ]),

  // Optional: eventType hint for filtering (can be derived from encrypted content)
  eventType: z.string().optional(),
});

export type SessionMessage = z.infer<typeof SessionMessageSchema>;

/**
 * Request body for encrypted message ingestion
 */
export const SessionMessagesRequestSchema = z.object({
  sessionId: z.string().min(1),
  deviceToken: z.string(),
  batchId: UlidSchema,
  messages: z.array(SessionMessageSchema),
});

export type SessionMessagesRequest = z.infer<
  typeof SessionMessagesRequestSchema
>;

/**
 * Response from message ingestion
 */
export const SessionMessagesResponseSchema = z.object({
  success: z.boolean(),
  batchId: z.string(),
  sessionId: z.string(),
  totalMessages: z.number(),
  communicationMessages: z.number(),
  conversationMessages: z.number(),
  streamedIds: z.number(),
  message: z.string().optional(),
  timestamp: z.number(),
});

export type SessionMessagesResponse = z.infer<
  typeof SessionMessagesResponseSchema
>;
