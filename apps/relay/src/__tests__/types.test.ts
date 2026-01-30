import { describe, expect, it } from "vitest";
import {
  AuthMessageSchema,
  createAuthFailure,
  createAuthSuccess,
  createDeliveryFailedEvent,
  createErrorEvent,
  createHeartbeatAckEvent,
  createMemberJoinedEvent,
  createMemberLeftEvent,
  createSubscribedEvent,
  createUnsubscribedEvent,
  parseRelayCommand,
  RelayCommandSchema,
  RelayEventSchema,
  SubscribeCommandSchema,
} from "../types/index.js";

describe("Relay Types", () => {
  describe("AuthMessageSchema", () => {
    it("should validate valid AUTH message", () => {
      const message = {
        type: "AUTH",
        deviceToken: "valid-token",
        deviceId: "550e8400-e29b-41d4-a716-446655440000",
      };

      const result = AuthMessageSchema.safeParse(message);
      expect(result.success).toBe(true);
    });

    it("should reject invalid AUTH message", () => {
      const message = {
        type: "AUTH",
        // missing deviceToken and deviceId
      };

      const result = AuthMessageSchema.safeParse(message);
      expect(result.success).toBe(false);
    });
  });

  describe("SubscribeCommandSchema", () => {
    it("should validate SUBSCRIBE command", () => {
      const command = {
        type: "SUBSCRIBE",
        sessionId: "550e8400-e29b-41d4-a716-446655440000",
      };

      const result = SubscribeCommandSchema.safeParse(command);
      expect(result.success).toBe(true);
    });
  });

  describe("RelayCommandSchema", () => {
    it("should parse AUTH command", () => {
      const command = {
        type: "AUTH",
        deviceToken: "token",
        deviceId: "550e8400-e29b-41d4-a716-446655440000",
      };

      const result = RelayCommandSchema.safeParse(command);
      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.type).toBe("AUTH");
      }
    });

    it("should parse HEARTBEAT command", () => {
      const command = { type: "HEARTBEAT" };

      const result = RelayCommandSchema.safeParse(command);
      expect(result.success).toBe(true);
    });
  });

  describe("parseRelayCommand", () => {
    it("should return success for valid command", () => {
      const result = parseRelayCommand({ type: "HEARTBEAT" });
      expect(result.success).toBe(true);
    });

    it("should return error for invalid command", () => {
      const result = parseRelayCommand({ type: "INVALID" });
      expect(result.success).toBe(false);
    });
  });

  describe("Event creators", () => {
    it("createAuthSuccess should create valid event", () => {
      const event = createAuthSuccess();
      expect(event.type).toBe("AUTH_RESULT");
      expect(event.success).toBe(true);
    });

    it("createAuthFailure should create valid event", () => {
      const event = createAuthFailure("Invalid token");
      expect(event.type).toBe("AUTH_RESULT");
      expect(event.success).toBe(false);
      expect(event.error).toBe("Invalid token");
    });

    it("createSubscribedEvent should create valid event", () => {
      const event = createSubscribedEvent("session-1", [
        { deviceId: "device-1", deviceName: "My Device" },
      ]);
      expect(event.type).toBe("SUBSCRIBED");
      expect(event.sessionId).toBe("session-1");
      expect(event.members).toHaveLength(1);
    });

    it("createUnsubscribedEvent should create valid event", () => {
      const event = createUnsubscribedEvent("session-1");
      expect(event.type).toBe("UNSUBSCRIBED");
      expect(event.sessionId).toBe("session-1");
    });

    it("createMemberJoinedEvent should create valid event", () => {
      const event = createMemberJoinedEvent(
        "session-1",
        "device-1",
        "My Device"
      );
      expect(event.type).toBe("MEMBER_JOINED");
      expect(event.sessionId).toBe("session-1");
      expect(event.deviceId).toBe("device-1");
      expect(event.deviceName).toBe("My Device");
    });

    it("createMemberLeftEvent should create valid event", () => {
      const event = createMemberLeftEvent("session-1", "device-1");
      expect(event.type).toBe("MEMBER_LEFT");
      expect(event.sessionId).toBe("session-1");
      expect(event.deviceId).toBe("device-1");
    });

    it("createDeliveryFailedEvent should create valid event", () => {
      const event = createDeliveryFailedEvent("DEVICE_OFFLINE", "session-1");
      expect(event.type).toBe("DELIVERY_FAILED");
      expect(event.reason).toBe("DEVICE_OFFLINE");
      expect(event.sessionId).toBe("session-1");
    });

    it("createHeartbeatAckEvent should create valid event", () => {
      const event = createHeartbeatAckEvent();
      expect(event.type).toBe("HEARTBEAT_ACK");
      expect(typeof event.timestamp).toBe("number");
    });

    it("createErrorEvent should create valid event", () => {
      const event = createErrorEvent("TEST_ERROR", "Test message");
      expect(event.type).toBe("ERROR");
      expect(event.code).toBe("TEST_ERROR");
      expect(event.message).toBe("Test message");
    });
  });

  describe("RelayEventSchema", () => {
    it("should validate all event types", () => {
      const events = [
        createAuthSuccess(),
        createAuthFailure("error"),
        createSubscribedEvent("550e8400-e29b-41d4-a716-446655440000", []),
        createUnsubscribedEvent("550e8400-e29b-41d4-a716-446655440000"),
        createMemberJoinedEvent(
          "550e8400-e29b-41d4-a716-446655440000",
          "550e8400-e29b-41d4-a716-446655440001"
        ),
        createMemberLeftEvent(
          "550e8400-e29b-41d4-a716-446655440000",
          "550e8400-e29b-41d4-a716-446655440001"
        ),
        createDeliveryFailedEvent("SESSION_NOT_FOUND"),
        createHeartbeatAckEvent(),
        createErrorEvent("ERROR", "message"),
      ];

      for (const event of events) {
        const result = RelayEventSchema.safeParse(event);
        expect(result.success).toBe(true);
      }
    });
  });
});
