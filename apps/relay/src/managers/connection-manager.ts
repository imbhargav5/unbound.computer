import type { WebSocket } from "ws";
import type { AuthContext } from "../types/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "connection-manager" });

/**
 * Connection state for a device
 */
export interface Connection {
  ws: WebSocket;
  deviceId: string;
  authenticated: boolean;
  authContext?: AuthContext;
  connectedAt: Date;
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
}

// Singleton instance
export const connectionManager = new ConnectionManager();
