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
