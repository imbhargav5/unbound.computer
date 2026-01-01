/**
 * WebRelayClient - WebSocket client for connecting to the Unbound relay
 * Used by web viewers to receive real-time session output
 */

import type {
  RemoteControlAck,
  RemoteControlAction,
  StreamChunk,
} from "@unbound/protocol";
import type {
  ConnectionState,
  RelayMessage,
  SessionParticipant,
  WebRelayClientOptions,
} from "./types";

const DEFAULT_RECONNECT_INTERVAL = 3000;
const DEFAULT_MAX_RECONNECT_ATTEMPTS = 5;
const DEFAULT_HEARTBEAT_INTERVAL = 30_000;

export class WebRelayClient {
  private ws: WebSocket | null = null;
  private connectionState: ConnectionState = "disconnected";
  private reconnectAttempts = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private sessionParticipants: Map<string, SessionParticipant> = new Map();

  private readonly options: Required<
    Pick<
      WebRelayClientOptions,
      | "relayUrl"
      | "sessionId"
      | "viewerId"
      | "authToken"
      | "permission"
      | "reconnectInterval"
      | "maxReconnectAttempts"
      | "heartbeatInterval"
    >
  > &
    WebRelayClientOptions;

  constructor(options: WebRelayClientOptions) {
    this.options = {
      ...options,
      permission: options.permission ?? "view_only",
      reconnectInterval:
        options.reconnectInterval ?? DEFAULT_RECONNECT_INTERVAL,
      maxReconnectAttempts:
        options.maxReconnectAttempts ?? DEFAULT_MAX_RECONNECT_ATTEMPTS,
      heartbeatInterval:
        options.heartbeatInterval ?? DEFAULT_HEARTBEAT_INTERVAL,
    };
  }

  /**
   * Connect to the relay server
   */
  connect(): void {
    if (this.ws && this.connectionState !== "disconnected") {
      return;
    }

    this.setConnectionState("connecting");

    try {
      this.ws = new WebSocket(this.options.relayUrl);
      this.setupEventHandlers();
    } catch (error) {
      this.handleError("CONNECTION_FAILED", "Failed to create WebSocket", true);
    }
  }

  /**
   * Disconnect from the relay server
   */
  disconnect(): void {
    this.cleanup();
    this.setConnectionState("disconnected");
  }

  /**
   * Send a remote control command (if permitted)
   */
  sendRemoteControl(action: RemoteControlAction, content?: string): boolean {
    if (!this.ws || this.connectionState !== "authenticated") {
      return false;
    }

    // Only allow control if permission is 'interact' or 'full_control'
    if (this.options.permission === "view_only" && action !== "INPUT") {
      this.handleError(
        "PERMISSION_DENIED",
        "View-only permission cannot send control commands",
        false
      );
      return false;
    }

    const message = {
      type: "REMOTE_CONTROL" as const,
      action,
      sessionId: this.options.sessionId,
      requesterId: this.options.viewerId,
      content,
      timestamp: Date.now(),
    };

    this.ws.send(JSON.stringify(message));
    return true;
  }

  /**
   * Send input to the session (if permitted)
   */
  sendInput(content: string): boolean {
    if (this.options.permission === "view_only") {
      this.handleError(
        "PERMISSION_DENIED",
        "View-only permission cannot send input",
        false
      );
      return false;
    }
    return this.sendRemoteControl("INPUT", content);
  }

  /**
   * Get current connection state
   */
  getConnectionState(): ConnectionState {
    return this.connectionState;
  }

  /**
   * Get session participants
   */
  getParticipants(): SessionParticipant[] {
    return [...this.sessionParticipants.values()];
  }

  /**
   * Check if connected and authenticated
   */
  isConnected(): boolean {
    return this.connectionState === "authenticated";
  }

  private setupEventHandlers(): void {
    if (!this.ws) return;

    this.ws.onopen = () => {
      this.reconnectAttempts = 0;
      this.setConnectionState("authenticating");
      this.authenticate();
    };

    this.ws.onmessage = (event) => {
      this.handleMessage(event.data);
    };

    this.ws.onclose = (event) => {
      this.stopHeartbeat();

      if (event.wasClean) {
        this.setConnectionState("disconnected");
      } else {
        this.attemptReconnect();
      }
    };

    this.ws.onerror = () => {
      this.handleError("WEBSOCKET_ERROR", "WebSocket error occurred", true);
    };
  }

  private authenticate(): void {
    if (!this.ws) return;

    const authMessage = {
      type: "AUTH",
      token: this.options.authToken,
      deviceName: "Web Session Viewer",
    };

    this.ws.send(JSON.stringify(authMessage));
  }

  private handleMessage(rawData: string): void {
    let data: unknown;
    try {
      data = JSON.parse(rawData);
    } catch {
      return;
    }

    const message = this.parseMessage(data);

    switch (message.type) {
      case "AUTH_SUCCESS":
        this.setConnectionState("authenticated");
        this.startHeartbeat();
        this.joinSession();
        break;

      case "AUTH_FAILED":
        this.handleError("AUTH_FAILED", message.reason, false);
        this.disconnect();
        break;

      case "SUBSCRIBED":
        this.handleSubscribed(message.members);
        break;

      case "MEMBER_JOINED":
        this.handleMemberJoined(message);
        break;

      case "MEMBER_LEFT":
        this.handleMemberLeft(message);
        break;

      case "STREAM_CHUNK":
        this.options.onStreamChunk?.(message.chunk);
        break;

      case "REMOTE_CONTROL_ACK":
        this.options.onRemoteControlAck?.(message.ack);
        break;

      case "ERROR":
        this.handleError(message.code, message.message, false);
        break;

      case "DELIVERY_FAILED":
        if (message.reason === "SESSION_NOT_FOUND") {
          this.options.onSessionEnded?.(this.options.sessionId);
        }
        break;

      case "HEARTBEAT_ACK":
        // Heartbeat acknowledged - connection is healthy
        break;

      case "UNKNOWN":
        // Try parsing as an envelope with stream data
        this.tryParseEnvelope(message.data);
        break;
    }
  }

  private parseMessage(data: unknown): RelayMessage {
    if (typeof data !== "object" || data === null) {
      return { type: "UNKNOWN", data };
    }

    const obj = data as Record<string, unknown>;
    const type = obj.type as string;

    switch (type) {
      case "AUTH_SUCCESS":
        return { type: "AUTH_SUCCESS", deviceId: obj.deviceId as string };

      case "AUTH_FAILED":
        return { type: "AUTH_FAILED", reason: obj.reason as string };

      case "SUBSCRIBED":
        return {
          type: "SUBSCRIBED",
          sessionId: obj.sessionId as string,
          members: (obj.members as SessionParticipant[]) ?? [],
        };

      case "UNSUBSCRIBED":
        return {
          type: "UNSUBSCRIBED",
          sessionId: obj.sessionId as string,
        };

      case "MEMBER_JOINED":
        return {
          type: "MEMBER_JOINED",
          sessionId: obj.sessionId as string,
          deviceId: obj.deviceId as string,
          deviceName: obj.deviceName as string | undefined,
          role: obj.role as string | undefined,
          permission: obj.permission as string | undefined,
        };

      case "MEMBER_LEFT":
        return {
          type: "MEMBER_LEFT",
          sessionId: obj.sessionId as string,
          deviceId: obj.deviceId as string,
          role: obj.role as string | undefined,
        };

      case "STREAM_CHUNK":
        return {
          type: "STREAM_CHUNK",
          chunk: obj as unknown as StreamChunk,
        };

      case "REMOTE_CONTROL_ACK":
        return {
          type: "REMOTE_CONTROL_ACK",
          ack: obj as unknown as RemoteControlAck,
        };

      case "HEARTBEAT_ACK":
        return {
          type: "HEARTBEAT_ACK",
          timestamp: obj.timestamp as number,
        };

      case "ERROR":
        return {
          type: "ERROR",
          code: obj.code as string,
          message: obj.message as string,
        };

      case "DELIVERY_FAILED":
        return {
          type: "DELIVERY_FAILED",
          reason: obj.reason as string,
          sessionId: obj.sessionId as string | undefined,
        };

      default:
        return { type: "UNKNOWN", data };
    }
  }

  private tryParseEnvelope(data: unknown): void {
    // Try to parse as a RelayEnvelope containing stream data
    if (typeof data !== "object" || data === null) return;

    const obj = data as Record<string, unknown>;

    // Check if it's an envelope with payload
    if (obj.payload && obj.type === "STREAM_CHUNK") {
      // The payload might be encrypted - for now, treat plaintext
      try {
        const payload =
          typeof obj.payload === "string"
            ? JSON.parse(obj.payload)
            : obj.payload;
        if (payload.type === "STREAM_CHUNK") {
          this.options.onStreamChunk?.(payload as StreamChunk);
        }
      } catch {
        // Encrypted or invalid payload
      }
    }
  }

  private joinSession(): void {
    if (!this.ws) return;

    const joinMessage = {
      type: "JOIN_SESSION",
      sessionId: this.options.sessionId,
      role: "viewer",
      permission: this.options.permission,
    };

    this.ws.send(JSON.stringify(joinMessage));
  }

  private handleSubscribed(members: SessionParticipant[]): void {
    this.sessionParticipants.clear();
    for (const member of members) {
      this.sessionParticipants.set(member.deviceId, member);
    }
  }

  private handleMemberJoined(data: {
    deviceId: string;
    deviceName?: string;
    role?: string;
    permission?: string;
    sessionId: string;
  }): void {
    const participant: SessionParticipant = {
      deviceId: data.deviceId,
      deviceName: data.deviceName,
      role: data.role,
      permission: data.permission,
    };
    this.sessionParticipants.set(data.deviceId, participant);

    this.options.onMemberJoined?.({
      sessionId: data.sessionId,
      deviceId: data.deviceId,
      deviceName: data.deviceName,
      role: data.role,
      permission: data.permission,
    });
  }

  private handleMemberLeft(data: {
    sessionId: string;
    deviceId: string;
    role?: string;
  }): void {
    this.sessionParticipants.delete(data.deviceId);

    this.options.onMemberLeft?.({
      sessionId: data.sessionId,
      deviceId: data.deviceId,
      role: data.role,
    });

    // If executor left, session may have ended
    if (data.role === "executor") {
      this.options.onSessionEnded?.(data.sessionId);
    }
  }

  private setConnectionState(state: ConnectionState): void {
    this.connectionState = state;
    this.options.onConnectionStateChange?.(state);
  }

  private handleError(
    code: string,
    message: string,
    recoverable: boolean
  ): void {
    this.setConnectionState("error");
    this.options.onError?.({ code, message, recoverable });
  }

  private attemptReconnect(): void {
    if (this.reconnectAttempts >= this.options.maxReconnectAttempts) {
      this.handleError(
        "MAX_RECONNECT_EXCEEDED",
        "Maximum reconnection attempts exceeded",
        false
      );
      this.setConnectionState("disconnected");
      return;
    }

    this.reconnectAttempts++;
    this.setConnectionState("connecting");

    this.reconnectTimer = setTimeout(() => {
      this.cleanup(false);
      this.connect();
    }, this.options.reconnectInterval);
  }

  private startHeartbeat(): void {
    this.heartbeatTimer = setInterval(() => {
      if (this.ws && this.connectionState === "authenticated") {
        this.ws.send(JSON.stringify({ type: "HEARTBEAT" }));
      }
    }, this.options.heartbeatInterval);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  private cleanup(resetState = true): void {
    this.stopHeartbeat();

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.ws) {
      this.ws.onopen = null;
      this.ws.onclose = null;
      this.ws.onmessage = null;
      this.ws.onerror = null;

      if (this.ws.readyState === WebSocket.OPEN) {
        // Leave session before closing
        this.ws.send(
          JSON.stringify({
            type: "LEAVE_SESSION",
            sessionId: this.options.sessionId,
          })
        );
        this.ws.close(1000, "Client disconnect");
      }

      this.ws = null;
    }

    if (resetState) {
      this.sessionParticipants.clear();
    }
  }
}

/**
 * Create a WebRelayClient instance
 */
export function createWebRelayClient(
  options: WebRelayClientOptions
): WebRelayClient {
  return new WebRelayClient(options);
}
