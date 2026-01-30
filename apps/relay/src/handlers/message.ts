import { parseEnvelope } from "@unbound/protocol";
import type { WebSocket } from "ws";
import { connectionManager, presenceManager } from "../managers/index.js";
import {
  createDeliveryFailedEvent,
  createErrorEvent,
  createHeartbeatAckEvent,
  parseRelayCommand,
} from "../types/index.js";
import { createLogger } from "../utils/index.js";
import { handleJoinSession, handleLeaveSession } from "./role.js";
import { handleSubscribe, handleUnsubscribe } from "./session.js";

const log = createLogger({ module: "message-handler" });

/**
 * Handle incoming WebSocket message
 */
export async function handleMessage(
  ws: WebSocket,
  deviceId: string,
  rawData: string
): Promise<void> {
  let data: unknown;

  // Parse JSON
  try {
    data = JSON.parse(rawData);
  } catch {
    log.warn({ deviceId }, "Invalid JSON received");
    ws.send(
      JSON.stringify(createErrorEvent("INVALID_JSON", "Invalid JSON format"))
    );
    return;
  }

  // Try to parse as relay command
  const commandResult = parseRelayCommand(data);

  if (commandResult.success) {
    const command = commandResult.data;

    log.debug(
      { deviceId, commandType: command.type },
      "Processing relay command"
    );

    switch (command.type) {
      case "AUTH": {
        // AUTH is now handled during WebSocket upgrade via verifyClient
        // Log a warning if a client still sends AUTH messages
        log.warn(
          { deviceId },
          "Received AUTH message but connection is already authenticated via upgrade"
        );
        // Send success to avoid breaking older clients
        ws.send(JSON.stringify({ type: "AUTH_RESULT", success: true }));
        return;
      }

      case "SUBSCRIBE":
        log.debug(
          {
            deviceId,
            sessionId: (command as { sessionId?: string }).sessionId,
          },
          "Device subscribing to session"
        );
        handleSubscribe(ws, deviceId, command);
        return;

      case "UNSUBSCRIBE":
        log.debug(
          {
            deviceId,
            sessionId: (command as { sessionId?: string }).sessionId,
          },
          "Device unsubscribing from session"
        );
        handleUnsubscribe(ws, deviceId, command);
        return;

      case "HEARTBEAT":
        log.debug({ deviceId }, "Heartbeat received");
        presenceManager.recordHeartbeat(deviceId);
        ws.send(JSON.stringify(createHeartbeatAckEvent()));
        return;

      case "JOIN_SESSION":
        log.debug(
          {
            deviceId,
            sessionId: (command as { sessionId?: string }).sessionId,
            role: (command as { role?: string }).role,
          },
          "Device joining session with role"
        );
        handleJoinSession(ws, deviceId, command);
        return;

      case "LEAVE_SESSION":
        log.debug(
          {
            deviceId,
            sessionId: (command as { sessionId?: string }).sessionId,
          },
          "Device leaving session"
        );
        handleLeaveSession(ws, deviceId, command);
        return;
    }
  }

  // Not a relay command - try to parse as RelayEnvelope
  const envelopeResult = parseEnvelope(data);

  if (!envelopeResult.success) {
    log.warn({ deviceId }, "Invalid message format");
    ws.send(
      JSON.stringify(
        createErrorEvent(
          "INVALID_MESSAGE",
          "Message must be a valid RelayEnvelope"
        )
      )
    );
    return;
  }

  // Check if authenticated
  if (!connectionManager.isAuthenticated(deviceId)) {
    log.warn({ deviceId }, "Unauthenticated message attempt");
    ws.send(
      JSON.stringify(
        createErrorEvent("NOT_AUTHENTICATED", "Must authenticate first")
      )
    );
    return;
  }

  const envelope = envelopeResult.data;

  // Crypto-blind routing: forward the raw message unchanged
  // We only inspect the envelope fields for routing, never the payload
  const { sessionId, senderId } = envelope;

  // Verify senderId matches authenticated device
  if (senderId !== deviceId) {
    log.warn({ deviceId, senderId }, "SenderId mismatch");
    ws.send(
      JSON.stringify(
        createErrorEvent(
          "SENDER_MISMATCH",
          "SenderId does not match authenticated device"
        )
      )
    );
    return;
  }

  // Check if session has members
  const members = connectionManager.getSessionMembers(sessionId);

  if (members.length === 0) {
    log.debug({ deviceId, sessionId }, "Session not found");
    ws.send(
      JSON.stringify(createDeliveryFailedEvent("SESSION_NOT_FOUND", sessionId))
    );
    return;
  }

  // Check if sender is in the session
  if (!members.includes(deviceId)) {
    log.warn({ deviceId, sessionId }, "Sender not in session");
    ws.send(
      JSON.stringify(
        createErrorEvent("NOT_IN_SESSION", "Must subscribe to session first")
      )
    );
    return;
  }

  // Broadcast to session members (exclude sender)
  const sent = connectionManager.broadcastToSession(
    sessionId,
    rawData, // Forward unchanged - crypto-blind
    deviceId
  );

  // If no one received the message, notify sender
  if (sent === 0 && members.length > 1) {
    // There are other members but none received it (all offline)
    log.debug(
      {
        deviceId,
        sessionId,
        envelopeType: envelope.type,
        totalMembers: members.length,
      },
      "Message delivery failed - all other members offline"
    );
    ws.send(
      JSON.stringify(createDeliveryFailedEvent("DEVICE_OFFLINE", sessionId))
    );
  }

  log.info(
    {
      deviceId,
      sessionId,
      envelopeType: envelope.type,
      recipientCount: sent,
      totalMembers: members.length,
    },
    "Message routed to session members (crypto-blind)"
  );
}
