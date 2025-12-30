import { EventEmitter } from "node:events";
import { parseEnvelope, type RelayEnvelope } from "@unbound/protocol";
import WebSocket from "ws";
import { config } from "../config.js";
import { logger } from "../utils/index.js";

/**
 * Relay client events
 */
interface RelayClientEvents {
  connected: [];
  disconnected: [code: number, reason: string];
  authenticated: [];
  authFailed: [error: string];
  message: [envelope: RelayEnvelope];
  subscribed: [
    sessionId: string,
    members: Array<{ deviceId: string; deviceName?: string }>,
  ];
  memberJoined: [sessionId: string, deviceId: string, deviceName?: string];
  memberLeft: [sessionId: string, deviceId: string];
  deliveryFailed: [reason: string, sessionId?: string];
  error: [error: Error];
}

/**
 * Relay client for persistent WebSocket connection
 */
export class RelayClient extends EventEmitter<RelayClientEvents> {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private isAuthenticated = false;
  private deviceToken: string;
  private deviceId: string;

  constructor(deviceToken: string, deviceId: string) {
    super();
    this.deviceToken = deviceToken;
    this.deviceId = deviceId;
  }

  /**
   * Connect to the relay server
   */
  connect(): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      return;
    }

    logger.debug(`Connecting to relay: ${config.relayUrl}`);

    this.ws = new WebSocket(config.relayUrl);

    this.ws.on("open", () => {
      logger.info("Connected to relay server");
      this.reconnectAttempts = 0;
      this.emit("connected");
      this.authenticate();
    });

    this.ws.on("message", (data) => {
      this.handleMessage(data.toString());
    });

    this.ws.on("close", (code, reason) => {
      logger.warn(`Disconnected from relay: ${code} ${reason}`);
      this.isAuthenticated = false;
      this.stopHeartbeat();
      this.emit("disconnected", code, reason.toString());
      this.scheduleReconnect();
    });

    this.ws.on("error", (error) => {
      logger.error(`Relay connection error: ${error.message}`);
      this.emit("error", error);
    });
  }

  /**
   * Disconnect from the relay server
   */
  disconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    this.stopHeartbeat();

    if (this.ws) {
      this.ws.close(1000, "Client disconnecting");
      this.ws = null;
    }
  }

  /**
   * Send AUTH message
   */
  private authenticate(): void {
    this.send({
      type: "AUTH",
      deviceToken: this.deviceToken,
      deviceId: this.deviceId,
    });
  }

  /**
   * Subscribe to a session
   */
  subscribe(sessionId: string): void {
    if (!this.isAuthenticated) {
      logger.warn("Cannot subscribe: not authenticated");
      return;
    }

    this.send({
      type: "SUBSCRIBE",
      sessionId,
    });
  }

  /**
   * Unsubscribe from a session
   */
  unsubscribe(sessionId: string): void {
    if (!this.isAuthenticated) {
      return;
    }

    this.send({
      type: "UNSUBSCRIBE",
      sessionId,
    });
  }

  /**
   * Send a relay envelope (encrypted message)
   */
  sendEnvelope(envelope: RelayEnvelope): void {
    if (!this.isAuthenticated) {
      logger.warn("Cannot send envelope: not authenticated");
      return;
    }

    this.send(envelope);
  }

  /**
   * Send raw message
   */
  private send(data: unknown): void {
    if (this.ws?.readyState !== WebSocket.OPEN) {
      logger.warn("Cannot send: WebSocket not open");
      return;
    }

    this.ws.send(JSON.stringify(data));
  }

  /**
   * Handle incoming message
   */
  private handleMessage(rawData: string): void {
    let data: Record<string, unknown>;

    try {
      data = JSON.parse(rawData);
    } catch {
      logger.warn("Invalid JSON from relay");
      return;
    }

    const type = data.type as string;

    switch (type) {
      case "AUTH_RESULT":
        if (data.success) {
          logger.info("Authenticated with relay");
          this.isAuthenticated = true;
          this.startHeartbeat();
          this.emit("authenticated");
        } else {
          logger.error(`Auth failed: ${data.error}`);
          this.emit("authFailed", data.error as string);
        }
        break;

      case "SUBSCRIBED":
        this.emit(
          "subscribed",
          data.sessionId as string,
          data.members as Array<{ deviceId: string; deviceName?: string }>
        );
        break;

      case "MEMBER_JOINED":
        this.emit(
          "memberJoined",
          data.sessionId as string,
          data.deviceId as string,
          data.deviceName as string | undefined
        );
        break;

      case "MEMBER_LEFT":
        this.emit(
          "memberLeft",
          data.sessionId as string,
          data.deviceId as string
        );
        break;

      case "DELIVERY_FAILED":
        this.emit(
          "deliveryFailed",
          data.reason as string,
          data.sessionId as string | undefined
        );
        break;

      case "HEARTBEAT_ACK":
        logger.debug("Heartbeat acknowledged");
        break;

      case "ERROR":
        logger.error(`Relay error: ${data.code} - ${data.message}`);
        break;

      default: {
        // Try to parse as RelayEnvelope (encrypted message)
        const envelopeResult = parseEnvelope(data);
        if (envelopeResult.success) {
          this.emit("message", envelopeResult.data);
        } else {
          logger.warn(`Unknown message type: ${type}`);
        }
      }
    }
  }

  /**
   * Start heartbeat timer
   */
  private startHeartbeat(): void {
    this.stopHeartbeat();

    this.heartbeatTimer = setInterval(() => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        this.send({ type: "HEARTBEAT" });
      }
    }, config.heartbeatInterval);
  }

  /**
   * Stop heartbeat timer
   */
  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  /**
   * Schedule reconnection with exponential backoff
   */
  private scheduleReconnect(): void {
    const delay = Math.min(
      config.wsReconnectDelay * 2 ** this.reconnectAttempts,
      config.wsMaxReconnectDelay
    );

    this.reconnectAttempts++;

    logger.info(
      `Reconnecting in ${delay / 1000}s (attempt ${this.reconnectAttempts})`
    );

    this.reconnectTimer = setTimeout(() => {
      this.connect();
    }, delay);
  }

  /**
   * Check if connected and authenticated
   */
  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN && this.isAuthenticated;
  }
}
