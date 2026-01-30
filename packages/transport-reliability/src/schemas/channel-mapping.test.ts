import { v7 as uuidv7 } from "uuid";
import { describe, expect, it } from "vitest";
import type { UnboundEvent } from "./any-event";
import { getChannelForEvent } from "./channel-mapping";

describe("getChannelForEvent", () => {
  describe("HANDSHAKE events", () => {
    it("should route PAIR_REQUEST to chatSecret channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "PAIR_REQUEST",
        plane: "HANDSHAKE",
        sessionId: null,
        payload: {
          remoteDeviceName: "Test Device",
          remoteDeviceId: uuidv7(),
          remotePublicKey: "test-key",
        },
      };

      expect(getChannelForEvent(event)).toBe("chatSecret");
    });

    it("should route PAIR_ACCEPTED to chatSecret channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "PAIR_ACCEPTED",
        plane: "HANDSHAKE",
        sessionId: null,
        payload: {
          executorDeviceId: uuidv7(),
          executorPublicKey: "test-key",
          executorDeviceName: "Executor",
        },
      };

      expect(getChannelForEvent(event)).toBe("chatSecret");
    });

    it("should route SESSION_CREATED to chatSecret channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "SESSION_CREATED",
        plane: "HANDSHAKE",
        sessionId: uuidv7(),
        payload: {},
      };

      expect(getChannelForEvent(event)).toBe("chatSecret");
    });

    it("should route PAIRING_APPROVED to chatSecret channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "PAIRING_APPROVED",
        plane: "HANDSHAKE",
        sessionId: null,
        payload: {
          pairingTokenId: uuidv7(),
          approvingDeviceId: uuidv7(),
          approvingDeviceName: "iOS Device",
        },
      };

      expect(getChannelForEvent(event)).toBe("chatSecret");
    });
  });

  describe("SESSION REMOTE_COMMAND events", () => {
    it("should route USER_PROMPT_COMMAND to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "USER_PROMPT_COMMAND",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "REMOTE_COMMAND",
        payload: {
          content: "Test prompt",
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route SESSION_PAUSE_COMMAND to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "SESSION_PAUSE_COMMAND",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "REMOTE_COMMAND",
        payload: {},
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route SESSION_RESUME_COMMAND to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "SESSION_RESUME_COMMAND",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "REMOTE_COMMAND",
        payload: {},
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route SESSION_STOP_COMMAND to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "SESSION_STOP_COMMAND",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "REMOTE_COMMAND",
        payload: {
          force: false,
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route TOOL_APPROVAL_COMMAND to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "TOOL_APPROVAL_COMMAND",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "REMOTE_COMMAND",
        payload: {
          toolUseId: "tool-123",
          approved: true,
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });
  });

  describe("SESSION EXECUTOR_UPDATE events", () => {
    it("should route EXECUTION_STARTED to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "EXECUTION_STARTED",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "EXECUTOR_UPDATE",
        payload: {},
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route OUTPUT_CHUNK to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "OUTPUT_CHUNK",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "EXECUTOR_UPDATE",
        payload: {
          text: "Console output...",
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route TOOL_STARTED to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "TOOL_STARTED",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "EXECUTOR_UPDATE",
        payload: {
          toolUseId: "tool-123",
          toolName: "bash",
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route TOOL_COMPLETED to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "TOOL_COMPLETED",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "EXECUTOR_UPDATE",
        payload: {
          toolUseId: "tool-123",
          toolName: "bash",
          success: true,
          durationMs: 1500,
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route FILE_CREATED to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "FILE_CREATED",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "EXECUTOR_UPDATE",
        payload: {
          filePath: "/path/to/file.ts",
          linesAdded: 100,
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route SESSION_HEARTBEAT to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "SESSION_HEARTBEAT",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "EXECUTOR_UPDATE",
        payload: {
          processAlive: true,
          uptime: 60_000,
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });

    it("should route STREAMING_THINKING to communication channel", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "STREAMING_THINKING",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "EXECUTOR_UPDATE",
        payload: {
          thinkingContent: "Analyzing the code...",
        },
      };

      expect(getChannelForEvent(event)).toBe("communication");
    });
  });

  describe("SESSION LOCAL_EXECUTION_COMMAND events", () => {
    it("should return null for LOCAL_EXECUTION_COMMAND (not sent to relay)", () => {
      const event: UnboundEvent = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "USER_PROMPT_COMMAND",
        plane: "SESSION",
        sessionId: uuidv7(),
        sessionEventType: "LOCAL_EXECUTION_COMMAND",
        payload: {
          content: "Local prompt typed on macOS",
        },
      };

      expect(getChannelForEvent(event)).toBe(null);
    });
  });

  describe("edge cases", () => {
    it("should default to conversation channel for unknown event structure", () => {
      const event = {
        opcode: "EVENT",
        eventId: uuidv7(),
        createdAt: Date.now(),
        type: "UNKNOWN_TYPE",
        payload: {},
      } as unknown as UnboundEvent;

      expect(getChannelForEvent(event)).toBe("conversation");
    });
  });
});
