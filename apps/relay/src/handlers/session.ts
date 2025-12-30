import type { WebSocket } from "ws";
import { connectionManager } from "../managers/index.js";
import type { SubscribeCommand, UnsubscribeCommand } from "../types/index.js";
import {
  createErrorEvent,
  createMemberJoinedEvent,
  createMemberLeftEvent,
  createSubscribedEvent,
  createUnsubscribedEvent,
} from "../types/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "session-handler" });

/**
 * Handle SUBSCRIBE command
 */
export function handleSubscribe(
  ws: WebSocket,
  deviceId: string,
  command: SubscribeCommand
): void {
  const { sessionId } = command;

  log.debug({ deviceId, sessionId }, "Processing SUBSCRIBE");

  // Check if authenticated
  if (!connectionManager.isAuthenticated(deviceId)) {
    log.warn({ deviceId }, "Unauthenticated subscribe attempt");
    ws.send(
      JSON.stringify(
        createErrorEvent("NOT_AUTHENTICATED", "Must authenticate first")
      )
    );
    return;
  }

  // Subscribe to the session
  const subscribed = connectionManager.subscribe(deviceId, sessionId);
  if (!subscribed) {
    log.warn({ deviceId, sessionId }, "Subscribe failed");
    ws.send(
      JSON.stringify(
        createErrorEvent("SUBSCRIBE_FAILED", "Failed to subscribe")
      )
    );
    return;
  }

  // Get current members (including self)
  const members = connectionManager.getSessionMemberInfo(sessionId);

  // Send SUBSCRIBED event to the client
  ws.send(JSON.stringify(createSubscribedEvent(sessionId, members)));

  // Get device info for broadcast
  const connection = connectionManager.getConnection(deviceId);
  const deviceName = connection?.authContext?.deviceName;

  // Broadcast MEMBER_JOINED to other session members
  const joinedEvent = createMemberJoinedEvent(sessionId, deviceId, deviceName);
  connectionManager.broadcastToSession(
    sessionId,
    JSON.stringify(joinedEvent),
    deviceId // Exclude self
  );

  log.info(
    { deviceId, sessionId, memberCount: members.length },
    "Client subscribed to session"
  );
}

/**
 * Handle UNSUBSCRIBE command
 */
export function handleUnsubscribe(
  ws: WebSocket,
  deviceId: string,
  command: UnsubscribeCommand
): void {
  const { sessionId } = command;

  log.debug({ deviceId, sessionId }, "Processing UNSUBSCRIBE");

  // Check if authenticated
  if (!connectionManager.isAuthenticated(deviceId)) {
    log.warn({ deviceId }, "Unauthenticated unsubscribe attempt");
    ws.send(
      JSON.stringify(
        createErrorEvent("NOT_AUTHENTICATED", "Must authenticate first")
      )
    );
    return;
  }

  // Unsubscribe from the session
  const unsubscribed = connectionManager.unsubscribe(deviceId, sessionId);
  if (!unsubscribed) {
    log.warn({ deviceId, sessionId }, "Unsubscribe failed - not in session");
    ws.send(
      JSON.stringify(
        createErrorEvent("NOT_IN_SESSION", "Not subscribed to this session")
      )
    );
    return;
  }

  // Send UNSUBSCRIBED event to the client
  ws.send(JSON.stringify(createUnsubscribedEvent(sessionId)));

  // Broadcast MEMBER_LEFT to remaining session members
  const leftEvent = createMemberLeftEvent(sessionId, deviceId);
  connectionManager.broadcastToSession(sessionId, JSON.stringify(leftEvent));

  log.info({ deviceId, sessionId }, "Client unsubscribed from session");
}
