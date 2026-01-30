import { z } from "zod";
import { AuthResultSchema } from "./auth.js";

/**
 * SUBSCRIBED event - successfully joined a session
 */
export const SubscribedEventSchema = z.object({
  type: z.literal("SUBSCRIBED"),
  sessionId: z.string().uuid(),
  members: z.array(
    z.object({
      deviceId: z.string().uuid(),
      deviceName: z.string().optional(),
    })
  ),
});

export type SubscribedEvent = z.infer<typeof SubscribedEventSchema>;

/**
 * UNSUBSCRIBED event - successfully left a session
 */
export const UnsubscribedEventSchema = z.object({
  type: z.literal("UNSUBSCRIBED"),
  sessionId: z.string().uuid(),
});

export type UnsubscribedEvent = z.infer<typeof UnsubscribedEventSchema>;

/**
 * MEMBER_JOINED event - another device joined the session
 */
export const MemberJoinedEventSchema = z.object({
  type: z.literal("MEMBER_JOINED"),
  sessionId: z.string().uuid(),
  deviceId: z.string().uuid(),
  deviceName: z.string().optional(),
});

export type MemberJoinedEvent = z.infer<typeof MemberJoinedEventSchema>;

/**
 * MEMBER_LEFT event - another device left the session
 */
export const MemberLeftEventSchema = z.object({
  type: z.literal("MEMBER_LEFT"),
  sessionId: z.string().uuid(),
  deviceId: z.string().uuid(),
});

export type MemberLeftEvent = z.infer<typeof MemberLeftEventSchema>;

/**
 * DELIVERY_FAILED event - message could not be delivered
 */
export const DeliveryFailedEventSchema = z.object({
  type: z.literal("DELIVERY_FAILED"),
  reason: z.enum(["DEVICE_OFFLINE", "SESSION_NOT_FOUND", "INVALID_MESSAGE"]),
  sessionId: z.string().uuid().optional(),
  targetDeviceId: z.string().uuid().optional(),
});

export type DeliveryFailedEvent = z.infer<typeof DeliveryFailedEventSchema>;

/**
 * HEARTBEAT_ACK event - response to HEARTBEAT command
 */
export const HeartbeatAckEventSchema = z.object({
  type: z.literal("HEARTBEAT_ACK"),
  timestamp: z.number(),
});

export type HeartbeatAckEvent = z.infer<typeof HeartbeatAckEventSchema>;

/**
 * ERROR event - generic error response
 */
export const ErrorEventSchema = z.object({
  type: z.literal("ERROR"),
  code: z.string(),
  message: z.string(),
});

export type ErrorEvent = z.infer<typeof ErrorEventSchema>;

/**
 * SESSION_MESSAGE - Real-time conversation message from Redis stream
 * Contains streaming content and file changes (encrypted)
 */
export const SessionMessageEventSchema = z.object({
  type: z.literal("SESSION_MESSAGE"),
  sessionId: z.string().uuid(),
  streamId: z.string(), // Redis stream message ID
  eventId: z.string().uuid(), // Original event ID
  messageId: z.string(), // Message ID for deduplication
  role: z.enum(["user", "assistant", "system"]),
  eventType: z.string(), // Event type (OUTPUT_CHUNK, etc.)
  contentEncrypted: z.string().optional(), // Base64 encoded encrypted content
  contentNonce: z.string().optional(), // Base64 encoded nonce
  createdAt: z.number(), // Unix timestamp
});

export type SessionMessageEvent = z.infer<typeof SessionMessageEventSchema>;

/**
 * REMOTE_COMMAND - Command sent from remote (iOS/web) to executor
 */
export const RemoteCommandEventSchema = z.object({
  type: z.literal("REMOTE_COMMAND"),
  sessionId: z.string().uuid(),
  streamId: z.string(), // Redis stream message ID
  eventId: z.string().uuid(), // Original event ID
  commandType: z.string(), // Command type (USER_PROMPT_COMMAND, etc.)
  contentEncrypted: z.string().optional(), // Base64 encoded encrypted content
  contentNonce: z.string().optional(), // Base64 encoded nonce
  createdAt: z.number(), // Unix timestamp
});

export type RemoteCommandEvent = z.infer<typeof RemoteCommandEventSchema>;

/**
 * EXECUTOR_UPDATE - State update sent from executor to remotes
 */
export const ExecutorUpdateEventSchema = z.object({
  type: z.literal("EXECUTOR_UPDATE"),
  sessionId: z.string().uuid(),
  streamId: z.string(), // Redis stream message ID
  eventId: z.string().uuid(), // Original event ID
  updateType: z.string(), // Update type (SESSION_STATE_CHANGED, etc.)
  contentEncrypted: z.string().optional(), // Base64 encoded encrypted content
  contentNonce: z.string().optional(), // Base64 encoded nonce
  createdAt: z.number(), // Unix timestamp
});

export type ExecutorUpdateEvent = z.infer<typeof ExecutorUpdateEventSchema>;

/**
 * @deprecated Use SessionMessageEventSchema instead
 */
export const ConversationEventSchema = z.object({
  type: z.literal("CONVERSATION_EVENT"),
  sessionId: z.string().uuid(),
  streamId: z.string(),
  eventId: z.string().uuid(),
  eventType: z.string(),
  payload: z.unknown(),
  createdAt: z.number(),
});

export type ConversationEvent = z.infer<typeof ConversationEventSchema>;

/**
 * @deprecated Use RemoteCommandEventSchema or ExecutorUpdateEventSchema instead
 */
export const CommunicationEventSchema = z.object({
  type: z.literal("COMMUNICATION_EVENT"),
  sessionId: z.string().uuid(),
  streamId: z.string(),
  eventId: z.string().uuid(),
  eventType: z.string(),
  payload: z.unknown(),
  createdAt: z.number(),
});

export type CommunicationEvent = z.infer<typeof CommunicationEventSchema>;

/**
 * All events the relay sends to clients
 */
export const RelayEventSchema = z.discriminatedUnion("type", [
  AuthResultSchema,
  SubscribedEventSchema,
  UnsubscribedEventSchema,
  MemberJoinedEventSchema,
  MemberLeftEventSchema,
  DeliveryFailedEventSchema,
  HeartbeatAckEventSchema,
  ErrorEventSchema,
  // New event types
  SessionMessageEventSchema,
  RemoteCommandEventSchema,
  ExecutorUpdateEventSchema,
  // Legacy (deprecated)
  ConversationEventSchema,
  CommunicationEventSchema,
]);

export type RelayEvent = z.infer<typeof RelayEventSchema>;

/**
 * Create a SUBSCRIBED event
 */
export function createSubscribedEvent(
  sessionId: string,
  members: Array<{ deviceId: string; deviceName?: string }>
): SubscribedEvent {
  return {
    type: "SUBSCRIBED",
    sessionId,
    members,
  };
}

/**
 * Create an UNSUBSCRIBED event
 */
export function createUnsubscribedEvent(sessionId: string): UnsubscribedEvent {
  return {
    type: "UNSUBSCRIBED",
    sessionId,
  };
}

/**
 * Create a MEMBER_JOINED event
 */
export function createMemberJoinedEvent(
  sessionId: string,
  deviceId: string,
  deviceName?: string
): MemberJoinedEvent {
  return {
    type: "MEMBER_JOINED",
    sessionId,
    deviceId,
    deviceName,
  };
}

/**
 * Create a MEMBER_LEFT event
 */
export function createMemberLeftEvent(
  sessionId: string,
  deviceId: string
): MemberLeftEvent {
  return {
    type: "MEMBER_LEFT",
    sessionId,
    deviceId,
  };
}

/**
 * Create a DELIVERY_FAILED event
 */
export function createDeliveryFailedEvent(
  reason: DeliveryFailedEvent["reason"],
  sessionId?: string,
  targetDeviceId?: string
): DeliveryFailedEvent {
  return {
    type: "DELIVERY_FAILED",
    reason,
    sessionId,
    targetDeviceId,
  };
}

/**
 * Create a HEARTBEAT_ACK event
 */
export function createHeartbeatAckEvent(): HeartbeatAckEvent {
  return {
    type: "HEARTBEAT_ACK",
    timestamp: Date.now(),
  };
}

/**
 * Create an ERROR event
 */
export function createErrorEvent(code: string, message: string): ErrorEvent {
  return {
    type: "ERROR",
    code,
    message,
  };
}

/**
 * Options for creating a SESSION_MESSAGE event
 */
interface SessionMessageEventOptions {
  sessionId: string;
  streamId: string;
  eventId: string;
  messageId: string;
  role: "user" | "assistant" | "system";
  eventType: string;
  contentEncrypted?: string;
  contentNonce?: string;
  createdAt: number;
}

/**
 * Create a SESSION_MESSAGE event
 */
export function createSessionMessageEvent(
  options: SessionMessageEventOptions
): SessionMessageEvent {
  return {
    type: "SESSION_MESSAGE",
    ...options,
  };
}

/**
 * Options for creating a REMOTE_COMMAND event
 */
interface RemoteCommandEventOptions {
  sessionId: string;
  streamId: string;
  eventId: string;
  commandType: string;
  contentEncrypted?: string;
  contentNonce?: string;
  createdAt: number;
}

/**
 * Create a REMOTE_COMMAND event
 */
export function createRemoteCommandEvent(
  options: RemoteCommandEventOptions
): RemoteCommandEvent {
  return {
    type: "REMOTE_COMMAND",
    ...options,
  };
}

/**
 * Options for creating an EXECUTOR_UPDATE event
 */
interface ExecutorUpdateEventOptions {
  sessionId: string;
  streamId: string;
  eventId: string;
  updateType: string;
  contentEncrypted?: string;
  contentNonce?: string;
  createdAt: number;
}

/**
 * Create an EXECUTOR_UPDATE event
 */
export function createExecutorUpdateEvent(
  options: ExecutorUpdateEventOptions
): ExecutorUpdateEvent {
  return {
    type: "EXECUTOR_UPDATE",
    ...options,
  };
}

/**
 * @deprecated Use createSessionMessageEvent instead
 */
interface ConversationEventOptions {
  sessionId: string;
  streamId: string;
  eventId: string;
  eventType: string;
  payload: unknown;
  createdAt: number;
}

/**
 * @deprecated Use createSessionMessageEvent instead
 */
export function createConversationEvent(
  options: ConversationEventOptions
): ConversationEvent {
  return {
    type: "CONVERSATION_EVENT",
    ...options,
  };
}

/**
 * @deprecated Use createRemoteCommandEvent or createExecutorUpdateEvent instead
 */
interface CommunicationEventOptions {
  sessionId: string;
  streamId: string;
  eventId: string;
  eventType: string;
  payload: unknown;
  createdAt: number;
}

/**
 * @deprecated Use createRemoteCommandEvent or createExecutorUpdateEvent instead
 */
export function createCommunicationEvent(
  options: CommunicationEventOptions
): CommunicationEvent {
  return {
    type: "COMMUNICATION_EVENT",
    ...options,
  };
}
