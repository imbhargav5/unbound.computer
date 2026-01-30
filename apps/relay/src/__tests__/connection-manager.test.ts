import { beforeEach, describe, expect, it, vi } from "vitest";
import type { WebSocket } from "ws";

// Mock the config before importing connection manager
vi.mock("../config.js", () => ({
  config: {
    PORT: 8080,
    HOST: "0.0.0.0",
    NODE_ENV: "test",
    LOG_LEVEL: "error",
    SUPABASE_URL: "http://localhost:54321",
    SUPABASE_SERVICE_ROLE_KEY: "test-key",
    HEARTBEAT_INTERVAL_MS: 30_000,
    CONNECTION_TIMEOUT_MS: 90_000,
    AUTH_TIMEOUT_MS: 10_000,
  },
}));

// Mock logger
vi.mock("../utils/logger.js", () => ({
  logger: {
    child: () => ({
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    }),
  },
  createLogger: () => ({
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

// Dynamic import after mocks
const { connectionManager } = await import("../managers/connection-manager.js");

function createMockWebSocket(): WebSocket {
  return {
    readyState: 1, // OPEN
    send: vi.fn(),
    close: vi.fn(),
  } as unknown as WebSocket;
}

describe("ConnectionManager", () => {
  beforeEach(() => {
    // Clear all connections between tests
    // Note: This is a workaround since we're using a singleton
    // In a real scenario, you might want to expose a reset method
  });

  describe("addConnection", () => {
    it("should add a new connection", () => {
      const ws = createMockWebSocket();
      const deviceId = "device-1";

      const connection = connectionManager.addConnection(deviceId, ws);

      expect(connection).toBeDefined();
      expect(connection.deviceId).toBe(deviceId);
      expect(connection.authenticated).toBe(false);
      expect(connection.ws).toBe(ws);
    });
  });

  describe("authenticate", () => {
    it("should authenticate a connection", () => {
      const ws = createMockWebSocket();
      const deviceId = "device-auth-1";

      connectionManager.addConnection(deviceId, ws);

      const result = connectionManager.authenticate(deviceId, {
        userId: "user-1",
        deviceId,
        deviceName: "Test Device",
      });

      expect(result).toBe(true);
      expect(connectionManager.isAuthenticated(deviceId)).toBe(true);
    });

    it("should return false for non-existent connection", () => {
      const result = connectionManager.authenticate("non-existent", {
        userId: "user-1",
        deviceId: "non-existent",
      });

      expect(result).toBe(false);
    });
  });

  describe("subscribe/unsubscribe", () => {
    it("should subscribe authenticated device to session", () => {
      const ws = createMockWebSocket();
      const deviceId = "device-sub-1";
      const sessionId = "session-1";

      connectionManager.addConnection(deviceId, ws);
      connectionManager.authenticate(deviceId, {
        userId: "user-1",
        deviceId,
      });

      const subscribed = connectionManager.subscribe(deviceId, sessionId);

      expect(subscribed).toBe(true);
      expect(connectionManager.getSessionMembers(sessionId)).toContain(
        deviceId
      );
    });

    it("should not subscribe unauthenticated device", () => {
      const ws = createMockWebSocket();
      const deviceId = "device-unauth-1";
      const sessionId = "session-2";

      connectionManager.addConnection(deviceId, ws);

      const subscribed = connectionManager.subscribe(deviceId, sessionId);

      expect(subscribed).toBe(false);
    });

    it("should unsubscribe device from session", () => {
      const ws = createMockWebSocket();
      const deviceId = "device-unsub-1";
      const sessionId = "session-3";

      connectionManager.addConnection(deviceId, ws);
      connectionManager.authenticate(deviceId, {
        userId: "user-1",
        deviceId,
      });
      connectionManager.subscribe(deviceId, sessionId);

      const unsubscribed = connectionManager.unsubscribe(deviceId, sessionId);

      expect(unsubscribed).toBe(true);
      expect(connectionManager.getSessionMembers(sessionId)).not.toContain(
        deviceId
      );
    });
  });

  describe("broadcastToSession", () => {
    it("should broadcast message to all session members except sender", () => {
      const ws1 = createMockWebSocket();
      const ws2 = createMockWebSocket();
      const device1 = "device-bc-1";
      const device2 = "device-bc-2";
      const sessionId = "session-bc-1";

      // Add and authenticate both devices
      connectionManager.addConnection(device1, ws1);
      connectionManager.authenticate(device1, {
        userId: "user-1",
        deviceId: device1,
      });
      connectionManager.subscribe(device1, sessionId);

      connectionManager.addConnection(device2, ws2);
      connectionManager.authenticate(device2, {
        userId: "user-2",
        deviceId: device2,
      });
      connectionManager.subscribe(device2, sessionId);

      // Broadcast from device1
      const message = JSON.stringify({ test: "hello" });
      const sent = connectionManager.broadcastToSession(
        sessionId,
        message,
        device1
      );

      expect(sent).toBe(1); // Only device2 should receive
      expect(ws2.send).toHaveBeenCalledWith(message);
      expect(ws1.send).not.toHaveBeenCalled();
    });
  });

  describe("sendToDevice", () => {
    it("should send message to online device", () => {
      const ws = createMockWebSocket();
      const deviceId = "device-send-1";

      connectionManager.addConnection(deviceId, ws);

      const sent = connectionManager.sendToDevice(
        deviceId,
        JSON.stringify({ test: "hello" })
      );

      expect(sent).toBe(true);
      expect(ws.send).toHaveBeenCalled();
    });

    it("should return false for offline device", () => {
      const sent = connectionManager.sendToDevice(
        "non-existent",
        JSON.stringify({ test: "hello" })
      );

      expect(sent).toBe(false);
    });
  });

  describe("removeConnection", () => {
    it("should remove connection and return left sessions", () => {
      const ws = createMockWebSocket();
      const deviceId = "device-rm-1";
      const sessionId = "session-rm-1";

      connectionManager.addConnection(deviceId, ws);
      connectionManager.authenticate(deviceId, {
        userId: "user-1",
        deviceId,
      });
      connectionManager.subscribe(deviceId, sessionId);

      const leftSessions = connectionManager.removeConnection(deviceId);

      expect(leftSessions).toContain(sessionId);
      expect(connectionManager.getConnection(deviceId)).toBeUndefined();
    });
  });
});
