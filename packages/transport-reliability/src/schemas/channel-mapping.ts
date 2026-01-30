import type { z } from "zod";
import type { UnboundEvent } from "./any-event";
import type { Channel } from "./relay-envelope";

/**
 * Maps event types to Redis stream channels
 * Relay server uses this to route messages without decrypting
 */
export const ChannelForEventType = {
  // Remote commands and executor updates go on communication Redis stream
  REMOTE_COMMAND: "communication" as const,

  // Executor updates also go on communication Redis stream (bidirectional communication)
  EXECUTOR_UPDATE: "communication" as const,

  // Local execution commands are not sent to relay (null = no channel)
  LOCAL_EXECUTION_COMMAND: null,

  // Handshake events go on chatSecret Redis stream (for initial pairing)
  HANDSHAKE: "chatSecret" as const,
} as const;

/**
 * Determine which Redis stream (channel) an event should be routed to
 * Returns null for LOCAL_EXECUTION_COMMAND events (not sent to relay)
 */
export function getChannelForEvent(
  event: z.infer<typeof UnboundEvent>
): Channel | null {
  if ("plane" in event) {
    if (event.plane === "HANDSHAKE") {
      return "chatSecret";
    }
    if (event.plane === "SESSION" && "sessionEventType" in event) {
      const channel = ChannelForEventType[event.sessionEventType];
      return channel ?? null;
    }
  }
  // Default fallback - conversation stream for non-communication events
  return "conversation";
}
