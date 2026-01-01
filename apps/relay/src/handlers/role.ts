import type { WebSocket } from "ws";
import { connectionManager } from "../managers/index.js";
import type {
  JoinSessionCommand,
  LeaveSessionCommand,
  RegisterRoleCommand,
} from "../types/index.js";
import {
  createErrorEvent,
  createMemberJoinedEvent,
  createMemberLeftEvent,
  createRoleAnnouncementEvent,
  createSubscribedEvent,
  createUnsubscribedEvent,
} from "../types/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "role-handler" });

/**
 * Handle REGISTER_ROLE command
 * Registers a device's role and account for cross-device routing
 */
export function handleRegisterRole(
  ws: WebSocket,
  deviceId: string,
  command: RegisterRoleCommand
): void {
  const { role, accountId, capabilities } = command;

  log.debug({ deviceId, role, accountId }, "Processing REGISTER_ROLE");

  // Check if authenticated
  if (!connectionManager.isAuthenticated(deviceId)) {
    log.warn({ deviceId }, "Unauthenticated role registration attempt");
    ws.send(
      JSON.stringify(
        createErrorEvent("NOT_AUTHENTICATED", "Must authenticate first")
      )
    );
    return;
  }

  // Register the role
  const registered = connectionManager.registerRole(
    deviceId,
    role,
    accountId,
    capabilities
  );

  if (!registered) {
    log.warn({ deviceId, role, accountId }, "Role registration failed");
    ws.send(
      JSON.stringify(
        createErrorEvent("ROLE_REGISTRATION_FAILED", "Failed to register role")
      )
    );
    return;
  }

  // Send role announcement event
  const announcement = createRoleAnnouncementEvent(
    deviceId,
    role,
    accountId,
    capabilities
  );
  ws.send(JSON.stringify(announcement));

  // Notify other devices in the same account
  const accountDevices = connectionManager.getAccountDevices(accountId);
  for (const otherDeviceId of accountDevices) {
    if (otherDeviceId !== deviceId) {
      connectionManager.sendToDevice(
        otherDeviceId,
        JSON.stringify(announcement)
      );
    }
  }

  log.info({ deviceId, role, accountId }, "Device role registered");
}

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

  // Broadcast MEMBER_LEFT with role info
  const leftEvent = {
    ...createMemberLeftEvent(sessionId, deviceId),
    role,
  };
  connectionManager.broadcastToSession(sessionId, JSON.stringify(leftEvent));

  log.info({ deviceId, sessionId, role }, "Device left session");
}
