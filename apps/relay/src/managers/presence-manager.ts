import { config } from "../config.js";
import { createMemberLeftEvent } from "../types/index.js";
import { createLogger } from "../utils/index.js";
import { connectionManager } from "./connection-manager.js";

const log = createLogger({ module: "presence-manager" });

/**
 * Presence state for a device
 */
interface PresenceState {
  deviceId: string;
  lastHeartbeat: Date;
  status: "online" | "away";
}

/**
 * Manages device presence and heartbeat tracking
 */
class PresenceManager {
  // deviceId -> PresenceState
  private presence = new Map<string, PresenceState>();

  // Interval for checking timeouts
  private checkInterval: ReturnType<typeof setInterval> | null = null;

  /**
   * Start presence monitoring
   */
  start(): void {
    if (this.checkInterval) {
      return;
    }

    // Check for timed out connections every 30 seconds
    this.checkInterval = setInterval(() => {
      this.checkTimeouts();
    }, config.HEARTBEAT_INTERVAL_MS);

    log.info("Presence manager started");
  }

  /**
   * Stop presence monitoring
   */
  stop(): void {
    if (this.checkInterval) {
      clearInterval(this.checkInterval);
      this.checkInterval = null;
    }

    log.info("Presence manager stopped");
  }

  /**
   * Record a heartbeat for a device
   */
  recordHeartbeat(deviceId: string): void {
    const existing = this.presence.get(deviceId);

    if (existing) {
      existing.lastHeartbeat = new Date();
      existing.status = "online";
    } else {
      this.presence.set(deviceId, {
        deviceId,
        lastHeartbeat: new Date(),
        status: "online",
      });
    }

    log.debug({ deviceId }, "Heartbeat recorded");
  }

  /**
   * Mark a device as connected (initial presence)
   */
  deviceConnected(deviceId: string): void {
    this.presence.set(deviceId, {
      deviceId,
      lastHeartbeat: new Date(),
      status: "online",
    });

    log.debug({ deviceId }, "Device connected");
  }

  /**
   * Mark a device as disconnected
   */
  deviceDisconnected(deviceId: string): void {
    this.presence.delete(deviceId);
    log.debug({ deviceId }, "Device disconnected");
  }

  /**
   * Get presence state for a device
   */
  getPresence(deviceId: string): PresenceState | undefined {
    return this.presence.get(deviceId);
  }

  /**
   * Check if a device is online (has recent heartbeat)
   */
  isOnline(deviceId: string): boolean {
    const state = this.presence.get(deviceId);
    if (!state) {
      return false;
    }

    const timeSinceHeartbeat = Date.now() - state.lastHeartbeat.getTime();
    return timeSinceHeartbeat < config.CONNECTION_TIMEOUT_MS;
  }

  /**
   * Check for timed out connections and handle them
   */
  private checkTimeouts(): void {
    const now = Date.now();
    const timedOut: string[] = [];

    for (const [deviceId, state] of this.presence.entries()) {
      const timeSinceHeartbeat = now - state.lastHeartbeat.getTime();

      if (timeSinceHeartbeat > config.CONNECTION_TIMEOUT_MS) {
        timedOut.push(deviceId);
      } else if (
        timeSinceHeartbeat > config.HEARTBEAT_INTERVAL_MS * 2 &&
        state.status === "online"
      ) {
        // Mark as away if no heartbeat for 2 intervals
        state.status = "away";
        log.debug({ deviceId }, "Device marked as away");
      }
    }

    // Handle timed out devices
    for (const deviceId of timedOut) {
      this.handleTimeout(deviceId);
    }

    if (timedOut.length > 0) {
      log.info({ count: timedOut.length }, "Devices timed out");
    }
  }

  /**
   * Handle a device timeout
   */
  private handleTimeout(deviceId: string): void {
    log.warn({ deviceId }, "Device timed out");

    // Get sessions the device was in before removing
    const connection = connectionManager.getConnection(deviceId);
    if (!connection) {
      this.presence.delete(deviceId);
      return;
    }

    // Remove from connection manager (returns sessions they left)
    const leftSessions = connectionManager.removeConnection(deviceId);

    // Broadcast MEMBER_LEFT to remaining session members
    for (const sessionId of leftSessions) {
      const event = createMemberLeftEvent(sessionId, deviceId);
      connectionManager.broadcastToSession(sessionId, JSON.stringify(event));
    }

    // Close the WebSocket connection
    try {
      connection.ws.close(1000, "Connection timed out");
    } catch {
      // Ignore close errors
    }

    // Remove presence
    this.presence.delete(deviceId);
  }

  /**
   * Get presence statistics
   */
  getStats(): {
    totalOnline: number;
    totalAway: number;
  } {
    let online = 0;
    let away = 0;

    for (const state of this.presence.values()) {
      if (state.status === "online") {
        online++;
      } else {
        away++;
      }
    }

    return {
      totalOnline: online,
      totalAway: away,
    };
  }
}

// Singleton instance
export const presenceManager = new PresenceManager();
