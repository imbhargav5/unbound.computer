import type { WebSocket } from "ws";
import type {
  AuthContext,
  DeviceRole,
  SessionParticipant,
} from "../types/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "connection-manager" });

/**
 * Device capabilities
 */
export interface DeviceCapabilities {
  canExecute?: boolean;
  canControl?: boolean;
  canView?: boolean;
}

/**
 * Connection state for a device
 */
export interface Connection {
  ws: WebSocket;
  deviceId: string;
  authenticated: boolean;
  authContext?: AuthContext;
  connectedAt: Date;
  /** Device role in the multi-device architecture */
  deviceRole?: DeviceRole;
  /** Account ID for cross-device routing */
  accountId?: string;
  /** Device capabilities */
  capabilities?: DeviceCapabilities;
}

/**
 * Session state with role-based tracking
 */
interface RoleBasedSession {
  sessionId: string;
  executorDeviceId?: string;
  controllerDeviceIds: Set<string>;
  viewerDeviceIds: Set<string>;
  participants: Map<string, SessionParticipant>;
  createdAt: Date;
}

/**
 * Manages WebSocket connections and session membership
 */
class ConnectionManager {
  // deviceId -> Connection
  private connections = new Map<string, Connection>();

  // sessionId -> Set of deviceIds
  private sessions = new Map<string, Set<string>>();

  // deviceId -> Set of sessionIds
  private deviceSessions = new Map<string, Set<string>>();

  // sessionId -> RoleBasedSession (for role-based routing)
  private roleBasedSessions = new Map<string, RoleBasedSession>();

  // accountId -> Set of deviceIds (for cross-device discovery)
  private accountDevices = new Map<string, Set<string>>();

  /**
   * Add a new connection (unauthenticated)
   */
  addConnection(deviceId: string, ws: WebSocket): Connection {
    const connection: Connection = {
      ws,
      deviceId,
      authenticated: false,
      connectedAt: new Date(),
    };
    this.connections.set(deviceId, connection);
    this.deviceSessions.set(deviceId, new Set());

    log.debug({ deviceId }, "Connection added");
    return connection;
  }

  /**
   * Remove a connection and clean up session membership
   */
  removeConnection(deviceId: string): string[] {
    const sessions = this.deviceSessions.get(deviceId);
    const leftSessions: string[] = [];

    if (sessions) {
      for (const sessionId of sessions) {
        this.sessions.get(sessionId)?.delete(deviceId);
        leftSessions.push(sessionId);

        // Clean up empty sessions
        if (this.sessions.get(sessionId)?.size === 0) {
          this.sessions.delete(sessionId);
        }
      }
    }

    this.connections.delete(deviceId);
    this.deviceSessions.delete(deviceId);

    log.debug({ deviceId, leftSessions }, "Connection removed");
    return leftSessions;
  }

  /**
   * Get a connection by device ID
   */
  getConnection(deviceId: string): Connection | undefined {
    return this.connections.get(deviceId);
  }

  /**
   * Mark a connection as authenticated
   */
  authenticate(deviceId: string, authContext: AuthContext): boolean {
    const connection = this.connections.get(deviceId);
    if (!connection) {
      return false;
    }

    connection.authenticated = true;
    connection.authContext = authContext;

    log.debug(
      { deviceId, userId: authContext.userId },
      "Connection authenticated"
    );
    return true;
  }

  /**
   * Check if a connection is authenticated
   */
  isAuthenticated(deviceId: string): boolean {
    return this.connections.get(deviceId)?.authenticated ?? false;
  }

  /**
   * Subscribe a device to a session
   */
  subscribe(deviceId: string, sessionId: string): boolean {
    if (!this.isAuthenticated(deviceId)) {
      return false;
    }

    // Add to sessions map
    if (!this.sessions.has(sessionId)) {
      this.sessions.set(sessionId, new Set());
    }
    this.sessions.get(sessionId)!.add(deviceId);

    // Add to device sessions map
    this.deviceSessions.get(deviceId)?.add(sessionId);

    log.debug({ deviceId, sessionId }, "Device subscribed to session");
    return true;
  }

  /**
   * Unsubscribe a device from a session
   */
  unsubscribe(deviceId: string, sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    session.delete(deviceId);
    this.deviceSessions.get(deviceId)?.delete(sessionId);

    // Clean up empty sessions
    if (session.size === 0) {
      this.sessions.delete(sessionId);
    }

    log.debug({ deviceId, sessionId }, "Device unsubscribed from session");
    return true;
  }

  /**
   * Get all device IDs in a session
   */
  getSessionMembers(sessionId: string): string[] {
    const session = this.sessions.get(sessionId);
    return session ? [...session] : [];
  }

  /**
   * Get session member info (deviceId + deviceName)
   */
  getSessionMemberInfo(
    sessionId: string
  ): Array<{ deviceId: string; deviceName?: string }> {
    const members = this.getSessionMembers(sessionId);
    return members.map((deviceId) => {
      const connection = this.connections.get(deviceId);
      return {
        deviceId,
        deviceName: connection?.authContext?.deviceName,
      };
    });
  }

  /**
   * Broadcast a message to all devices in a session
   */
  broadcastToSession(
    sessionId: string,
    message: string,
    excludeDeviceId?: string
  ): number {
    const members = this.getSessionMembers(sessionId);
    let sent = 0;

    for (const deviceId of members) {
      if (deviceId === excludeDeviceId) {
        continue;
      }

      if (this.sendToDevice(deviceId, message)) {
        sent++;
      }
    }

    log.debug(
      { sessionId, sent, total: members.length, excluded: excludeDeviceId },
      "Broadcast to session"
    );
    return sent;
  }

  /**
   * Send a message to a specific device
   * Returns false if device is offline
   */
  sendToDevice(deviceId: string, message: string): boolean {
    const connection = this.connections.get(deviceId);
    if (!connection || connection.ws.readyState !== 1) {
      return false;
    }

    try {
      connection.ws.send(message);
      return true;
    } catch {
      log.warn({ deviceId }, "Failed to send message to device");
      return false;
    }
  }

  /**
   * Check if a device is online
   */
  isDeviceOnline(deviceId: string): boolean {
    const connection = this.connections.get(deviceId);
    return connection?.ws.readyState === 1;
  }

  /**
   * Get connection statistics
   */
  getStats(): {
    totalConnections: number;
    authenticatedConnections: number;
    totalSessions: number;
  } {
    let authenticatedConnections = 0;
    for (const connection of this.connections.values()) {
      if (connection.authenticated) {
        authenticatedConnections++;
      }
    }

    return {
      totalConnections: this.connections.size,
      authenticatedConnections,
      totalSessions: this.sessions.size,
    };
  }

  // ========================================
  // Role-based routing methods
  // ========================================

  /**
   * Register a device's role and account
   */
  registerRole(
    deviceId: string,
    role: DeviceRole,
    accountId: string,
    capabilities?: DeviceCapabilities
  ): boolean {
    const connection = this.connections.get(deviceId);
    if (!connection?.authenticated) {
      return false;
    }

    connection.deviceRole = role;
    connection.accountId = accountId;
    connection.capabilities = capabilities;

    // Track device by account
    if (!this.accountDevices.has(accountId)) {
      this.accountDevices.set(accountId, new Set());
    }
    this.accountDevices.get(accountId)!.add(deviceId);

    log.debug({ deviceId, role, accountId }, "Device role registered");
    return true;
  }

  /**
   * Join a session with a specific role
   */
  joinSessionWithRole(
    deviceId: string,
    sessionId: string,
    role: DeviceRole,
    permission: "view_only" | "interact" | "full_control" = "view_only"
  ): boolean {
    const connection = this.connections.get(deviceId);
    if (!connection?.authenticated) {
      return false;
    }

    // Initialize role-based session if needed
    if (!this.roleBasedSessions.has(sessionId)) {
      this.roleBasedSessions.set(sessionId, {
        sessionId,
        controllerDeviceIds: new Set(),
        viewerDeviceIds: new Set(),
        participants: new Map(),
        createdAt: new Date(),
      });
    }

    const session = this.roleBasedSessions.get(sessionId)!;

    // Add to role-specific set
    switch (role) {
      case "executor":
        session.executorDeviceId = deviceId;
        break;
      case "controller":
        session.controllerDeviceIds.add(deviceId);
        break;
      case "viewer":
        session.viewerDeviceIds.add(deviceId);
        break;
    }

    // Add participant info
    session.participants.set(deviceId, {
      deviceId,
      deviceName: connection.authContext?.deviceName,
      role,
      permission,
      joinedAt: new Date(),
      isActive: true,
    });

    // Also add to legacy session tracking
    this.subscribe(deviceId, sessionId);

    log.debug(
      { deviceId, sessionId, role, permission },
      "Device joined session with role"
    );
    return true;
  }

  /**
   * Leave a session (role-based)
   */
  leaveSession(deviceId: string, sessionId: string): boolean {
    const session = this.roleBasedSessions.get(sessionId);
    if (!session) {
      return this.unsubscribe(deviceId, sessionId);
    }

    // Remove from role-specific sets
    if (session.executorDeviceId === deviceId) {
      session.executorDeviceId = undefined;
    }
    session.controllerDeviceIds.delete(deviceId);
    session.viewerDeviceIds.delete(deviceId);
    session.participants.delete(deviceId);

    // Clean up empty sessions
    if (
      !session.executorDeviceId &&
      session.controllerDeviceIds.size === 0 &&
      session.viewerDeviceIds.size === 0
    ) {
      this.roleBasedSessions.delete(sessionId);
    }

    // Also remove from legacy tracking
    this.unsubscribe(deviceId, sessionId);

    log.debug({ deviceId, sessionId }, "Device left session");
    return true;
  }

  /**
   * Get the executor device for a session
   */
  getSessionExecutor(sessionId: string): string | undefined {
    return this.roleBasedSessions.get(sessionId)?.executorDeviceId;
  }

  /**
   * Get all controller devices for a session
   */
  getSessionControllers(sessionId: string): string[] {
    const session = this.roleBasedSessions.get(sessionId);
    return session ? [...session.controllerDeviceIds] : [];
  }

  /**
   * Get all viewer devices for a session
   */
  getSessionViewers(sessionId: string): string[] {
    const session = this.roleBasedSessions.get(sessionId);
    return session ? [...session.viewerDeviceIds] : [];
  }

  /**
   * Get all participants with their roles for a session
   */
  getSessionParticipants(sessionId: string): SessionParticipant[] {
    const session = this.roleBasedSessions.get(sessionId);
    return session ? [...session.participants.values()] : [];
  }

  /**
   * Route message from executor to all viewers
   * Used for streaming Claude output to all viewers
   */
  routeExecutorToViewers(
    sessionId: string,
    message: string,
    executorDeviceId: string
  ): number {
    const session = this.roleBasedSessions.get(sessionId);
    if (!session || session.executorDeviceId !== executorDeviceId) {
      log.warn({ sessionId, executorDeviceId }, "Invalid executor for session");
      return 0;
    }

    let sent = 0;
    for (const viewerId of session.viewerDeviceIds) {
      if (this.sendToDevice(viewerId, message)) {
        sent++;
      }
    }

    // Also send to controllers
    for (const controllerId of session.controllerDeviceIds) {
      if (this.sendToDevice(controllerId, message)) {
        sent++;
      }
    }

    log.debug(
      { sessionId, sent, viewers: session.viewerDeviceIds.size },
      "Routed executor message to viewers"
    );
    return sent;
  }

  /**
   * Route message from controller to executor
   * Used for remote control commands (pause, stop, resume)
   */
  routeControllerToExecutor(
    sessionId: string,
    message: string,
    controllerDeviceId: string
  ): boolean {
    const session = this.roleBasedSessions.get(sessionId);
    if (!session) {
      return false;
    }

    // Verify sender is a controller
    if (!session.controllerDeviceIds.has(controllerDeviceId)) {
      log.warn(
        { sessionId, controllerDeviceId },
        "Non-controller tried to send to executor"
      );
      return false;
    }

    const executorId = session.executorDeviceId;
    if (!executorId) {
      log.warn({ sessionId }, "No executor in session");
      return false;
    }

    return this.sendToDevice(executorId, message);
  }

  /**
   * Route message from viewer to executor (if permitted)
   * Used for input from web viewers with interact/full_control permission
   */
  routeViewerToExecutor(
    sessionId: string,
    message: string,
    viewerDeviceId: string
  ): boolean {
    const session = this.roleBasedSessions.get(sessionId);
    if (!session) {
      return false;
    }

    const participant = session.participants.get(viewerDeviceId);
    if (!participant || participant.permission === "view_only") {
      log.warn(
        { sessionId, viewerDeviceId, permission: participant?.permission },
        "Viewer without permission tried to send to executor"
      );
      return false;
    }

    const executorId = session.executorDeviceId;
    if (!executorId) {
      return false;
    }

    return this.sendToDevice(executorId, message);
  }

  /**
   * Get all devices for an account
   */
  getAccountDevices(accountId: string): string[] {
    const devices = this.accountDevices.get(accountId);
    return devices ? [...devices] : [];
  }

  /**
   * Get online devices for an account with their roles
   */
  getOnlineAccountDevices(
    accountId: string
  ): Array<{ deviceId: string; role?: DeviceRole; deviceName?: string }> {
    const deviceIds = this.getAccountDevices(accountId);
    return deviceIds
      .filter((deviceId) => this.isDeviceOnline(deviceId))
      .map((deviceId) => {
        const connection = this.connections.get(deviceId);
        return {
          deviceId,
          role: connection?.deviceRole,
          deviceName: connection?.authContext?.deviceName,
        };
      });
  }

  /**
   * Get device role
   */
  getDeviceRole(deviceId: string): DeviceRole | undefined {
    return this.connections.get(deviceId)?.deviceRole;
  }
}

// Singleton instance
export const connectionManager = new ConnectionManager();
