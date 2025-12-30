import type { WebSocket } from "ws";
import { config } from "../config.js";
import { connectionManager, presenceManager } from "../managers/index.js";
import { createMemberLeftEvent } from "../types/index.js";
import { createLogger } from "../utils/index.js";
import { handleMessage } from "./message.js";

const log = createLogger({ module: "connection-handler" });

/**
 * Generate a temporary device ID for unauthenticated connections
 */
function generateTempDeviceId(): string {
  return `temp-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

/**
 * Handle new WebSocket connection
 */
export function handleConnection(ws: WebSocket): void {
  // Generate temp ID until auth provides real device ID
  const tempDeviceId = generateTempDeviceId();

  log.debug({ tempDeviceId }, "New connection");

  // Add connection (unauthenticated)
  connectionManager.addConnection(tempDeviceId, ws);

  // Set up auth timeout
  const authTimeout = setTimeout(() => {
    if (!connectionManager.isAuthenticated(tempDeviceId)) {
      log.warn({ tempDeviceId }, "Auth timeout - closing connection");
      ws.close(4001, "Authentication timeout");
    }
  }, config.AUTH_TIMEOUT_MS);

  // Handle messages
  ws.on("message", async (data) => {
    try {
      const message = data.toString();

      // Get the actual device ID if authenticated
      const connection = connectionManager.getConnection(tempDeviceId);
      const deviceId = connection?.authContext?.deviceId || tempDeviceId;

      await handleMessage(ws, deviceId, message);

      // If just authenticated, update the connection map
      if (
        connection?.authenticated &&
        connection.authContext?.deviceId &&
        connection.authContext.deviceId !== tempDeviceId
      ) {
        // The connection manager will be updated when AUTH succeeds
        // with the real device ID. For now, we keep using tempDeviceId.
      }
    } catch (error) {
      log.error({ error, tempDeviceId }, "Message handling error");
    }
  });

  // Handle close
  ws.on("close", (code, reason) => {
    clearTimeout(authTimeout);

    const connection = connectionManager.getConnection(tempDeviceId);
    const deviceId = connection?.authContext?.deviceId || tempDeviceId;

    log.debug(
      { deviceId, code, reason: reason.toString() },
      "Connection closed"
    );

    // Get sessions before removing connection
    const leftSessions = connectionManager.removeConnection(tempDeviceId);

    // Broadcast MEMBER_LEFT to remaining session members
    for (const sessionId of leftSessions) {
      const event = createMemberLeftEvent(sessionId, deviceId);
      connectionManager.broadcastToSession(sessionId, JSON.stringify(event));
    }

    // Remove presence
    presenceManager.deviceDisconnected(deviceId);
  });

  // Handle errors
  ws.on("error", (error) => {
    log.error({ error, tempDeviceId }, "WebSocket error");
  });
}
