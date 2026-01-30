import type { WebSocket } from "ws";
import { connectionManager } from "../managers/index.js";
import type {
  JoinSessionCommand,
  LeaveSessionCommand,
} from "../types/index.js";
import {
  createErrorEvent,
  createMemberJoinedEvent,
  createMemberLeftEvent,
  createSubscribedEvent,
  createUnsubscribedEvent,
} from "../types/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "role-handler" });

/**
 * Handle JOIN_SESSION command
 * Joins a session with a specific role for role-based routing
 */
export function handleJoinSession(
  ws: WebSocket,
  deviceId: string,
  command: JoinSessionCommand
): void {
  const { sessionId, role, permission = "view_only" } = command;

  log.debug(
    { deviceId, sessionId, role, permission },
    "Processing JOIN_SESSION"
  );

  // Check if authenticated
  if (!connectionManager.isAuthenticated(deviceId)) {
    log.warn({ deviceId }, "Unauthenticated join session attempt");
    ws.send(
      JSON.stringify(
        createErrorEvent("NOT_AUTHENTICATED", "Must authenticate first")
      )
    );
    return;
  }

  // Join the session with role
  const joined = connectionManager.joinSessionWithRole(
    deviceId,
    sessionId,
    role,
    permission
  );

  if (!joined) {
    log.warn({ deviceId, sessionId, role }, "Join session failed");
    ws.send(
      JSON.stringify(
        createErrorEvent("JOIN_SESSION_FAILED", "Failed to join session")
      )
    );
    return;
  }

  // Get current participants with roles
  const participants = connectionManager.getSessionParticipants(sessionId);
  const memberInfo = participants.map((p) => ({
    deviceId: p.deviceId,
    deviceName: p.deviceName,
    role: p.role,
    permission: p.permission,
  }));

  // Send SUBSCRIBED event with enhanced member info
  ws.send(JSON.stringify(createSubscribedEvent(sessionId, memberInfo)));

  // Get device info for broadcast
  const connection = connectionManager.getConnection(deviceId);
  const deviceName = connection?.authContext?.deviceName;

  // Broadcast MEMBER_JOINED with role info to other session members
  const joinedEvent = {
    ...createMemberJoinedEvent(sessionId, deviceId, deviceName),
    role,
    permission,
  };
  connectionManager.broadcastToSession(
    sessionId,
    JSON.stringify(joinedEvent),
    deviceId
  );

  // Notify offline session members via APNs (async, fire-and-forget)
  import("../services/index.js").then(({ notificationManager }) => {
    // If an executor joins, notify controllers about session start
    if (role === "executor") {
      notificationManager.notifySessionMembers(
        sessionId,
        "session_started",
        { executorName: deviceName, sessionId },
        deviceId
      );
    } else {
      notificationManager.notifySessionMembers(
        sessionId,
        "member_joined",
        { memberName: deviceName, role, sessionId },
        deviceId
      );
    }
  });

  log.info(
    { deviceId, sessionId, role, permission, memberCount: participants.length },
    "Device joined session with role"
  );
}

/**
 * Handle LEAVE_SESSION command
 */
export function handleLeaveSession(
  ws: WebSocket,
  deviceId: string,
  command: LeaveSessionCommand
): void {
  const { sessionId } = command;

  log.debug({ deviceId, sessionId }, "Processing LEAVE_SESSION");

  // Check if authenticated
  if (!connectionManager.isAuthenticated(deviceId)) {
    log.warn({ deviceId }, "Unauthenticated leave session attempt");
    ws.send(
      JSON.stringify(
        createErrorEvent("NOT_AUTHENTICATED", "Must authenticate first")
      )
    );
    return;
  }

  // Get role before leaving (for logging)
  const role = connectionManager.getDeviceRole(deviceId);

  // Leave the session
  const left = connectionManager.leaveSession(deviceId, sessionId);
  if (!left) {
    log.warn({ deviceId, sessionId }, "Leave session failed - not in session");
    ws.send(
      JSON.stringify(createErrorEvent("NOT_IN_SESSION", "Not in this session"))
    );
    return;
  }

  // Send UNSUBSCRIBED event
  ws.send(JSON.stringify(createUnsubscribedEvent(sessionId)));

  // Get device info for notification
  const connection = connectionManager.getConnection(deviceId);
  const deviceName = connection?.authContext?.deviceName;

  // Broadcast MEMBER_LEFT with role info
  const leftEvent = {
    ...createMemberLeftEvent(sessionId, deviceId),
    role,
  };
  connectionManager.broadcastToSession(sessionId, JSON.stringify(leftEvent));

  // Notify offline session members via APNs (async, fire-and-forget)
  import("../services/index.js").then(({ notificationManager }) => {
    // If an executor leaves, notify about session end
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
  });

  log.info({ deviceId, sessionId, role }, "Device left session");
}
