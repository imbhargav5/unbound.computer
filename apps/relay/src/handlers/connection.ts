import type { WebSocket } from "ws";
import { connectionManager, presenceManager } from "../managers/index.js";
import type { AuthContext } from "../types/index.js";
import { createMemberLeftEvent } from "../types/index.js";
import { createLogger } from "../utils/index.js";
import { handleMessage } from "./message.js";

const log = createLogger({ module: "connection-handler" });

/**
 * Handle new WebSocket connection (pre-authenticated via verifyClient)
 */
export function handleConnection(
  ws: WebSocket,
  authContext: AuthContext
): void {
  const deviceId = authContext.deviceId;
  const connectionTime = Date.now();

  log.info(
    {
      deviceId,
      deviceName: authContext.deviceName,
      userId: authContext.userId?.slice(0, 8),
      connectionTime: new Date(connectionTime).toISOString(),
    },
    "WebSocket connection established (pre-authenticated)"
  );

  // Add connection (already authenticated)
  connectionManager.addAuthenticatedConnection(deviceId, ws, authContext);

  // Record presence
  presenceManager.deviceConnected(deviceId);

  // Handle messages
  ws.on("message", async (data) => {
    try {
      const message = data.toString();
      await handleMessage(ws, deviceId, message);
    } catch (error) {
      log.error({ error, deviceId }, "Message handling error");
    }
  });

  // Handle close
  ws.on("close", (code, reason) => {
    const connection = connectionManager.getConnection(deviceId);
    const connectionDuration = Date.now() - connectionTime;

    log.info(
      {
        deviceId,
        code,
        reason: reason.toString(),
        connectionDurationMs: connectionDuration,
        deviceName: authContext.deviceName,
      },
      "WebSocket connection closed"
    );

    // Get device role before removing connection
    const role = connectionManager.getDeviceRole(deviceId);
    const deviceName = authContext.deviceName;

    // Get sessions before removing connection
    const leftSessions = connectionManager.removeConnection(deviceId);

    // Broadcast MEMBER_LEFT to remaining session members
    for (const sessionId of leftSessions) {
      const event = createMemberLeftEvent(sessionId, deviceId);
      connectionManager.broadcastToSession(sessionId, JSON.stringify(event));
    }

    // Notify offline session members via APNs (async, fire-and-forget)
    if (leftSessions.length > 0) {
      import("../services/index.js").then(({ notificationManager }) => {
        for (const sessionId of leftSessions) {
          // If an executor disconnects, notify about session end
          if (role === "executor") {
            notificationManager.notifySessionMembers(
              sessionId,
              "session_ended",
              { executorName: deviceName, sessionId },
              deviceId
            );
            // Also end any Live Activities for this session
            notificationManager.updateLiveActivities(
              sessionId,
              { status: "ended", activeSessionCount: 0 },
              "end"
            );
          } else {
            notificationManager.notifySessionMembers(
              sessionId,
              "member_left",
              { memberName: deviceName, role, sessionId },
              deviceId
            );
          }
        }
      });
    }

    // Remove presence
    presenceManager.deviceDisconnected(deviceId);
  });

  // Handle errors
  ws.on("error", (error) => {
    log.error(
      {
        error,
        deviceId,
        deviceName: authContext.deviceName,
      },
      "WebSocket error occurred"
    );
  });
}
