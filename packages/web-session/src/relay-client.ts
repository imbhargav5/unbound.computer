import type { ControlMessage, RelayEnvelope } from "@unbound/protocol";
import type { WebSessionManager } from "./manager.js";

/**
 * Session message content (application-level message)
 * This represents the decrypted content of a session message.
 */
export interface SessionMessage {
  type: string;
  [key: string]: unknown;
}

/**
 * Connection state for the relay client
 */
export type ConnectionState =
  | "disconnected"
  | "connecting"
  | "connected"
  | "reconnecting"
  | "error";

/**
 * Event handlers for the relay client
 */
export interface WebRelayClientEvents {
  onMessage?: (sessionId: string, message: SessionMessage) => void;
  onControl?: (message: ControlMessage) => void;
  onConnectionChange?: (state: ConnectionState) => void;
  onError?: (error: Error) => void;
  onPresence?: (
    deviceId: string,
    status: "online" | "offline" | "away"
  ) => void;
}

/**
 * Options for the web relay client
 */
export interface WebRelayClientOptions {
  /** Relay server WebSocket URL */
  relayUrl: string;
  /** Session manager for encryption */
  sessionManager: WebSessionManager;
  /** Event handlers */
  events?: WebRelayClientEvents;
  /** Reconnect attempts */
  maxReconnectAttempts?: number;
  /** Reconnect delay (ms) */
  reconnectDelay?: number;
}

/**
 * WebRelayClient handles the WebSocket connection to the relay server
 * for encrypted real-time communication.
 */
export class WebRelayClient {
  private ws: WebSocket | null = null;
  private options: Required<WebRelayClientOptions>;
  private connectionState: ConnectionState = "disconnected";
  private reconnectAttempts = 0;
  private reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
  private subscribedSessions = new Set<string>();
  private heartbeatInterval: ReturnType<typeof setInterval> | null = null;

  constructor(options: WebRelayClientOptions) {
    this.options = {
      relayUrl: options.relayUrl,
      sessionManager: options.sessionManager,
      events: options.events ?? {},
      maxReconnectAttempts: options.maxReconnectAttempts ?? 10,
      reconnectDelay: options.reconnectDelay ?? 1000,
    };
  }

  /**
   * Connect to the relay server
   */
  async connect(): Promise<void> {
    if (this.connectionState === "connected") {
      return;
    }

    if (!this.options.sessionManager.isAuthorized()) {
      throw new Error("Web session not authorized");
    }

    this.setConnectionState("connecting");

    return new Promise((resolve, reject) => {
      try {
        const session = this.options.sessionManager.getState();
        if (!session) {
          reject(new Error("No web session"));
          return;
        }

        // Connect to relay with session token in query
        const url = new URL(this.options.relayUrl);
        url.searchParams.set("webSessionId", session.id);
        url.searchParams.set("token", session.sessionToken);

        this.ws = new WebSocket(url.toString());

        this.ws.onopen = () => {
          this.setConnectionState("connected");
          this.reconnectAttempts = 0;
          this.startHeartbeat();

          // Resubscribe to sessions
          for (const sessionId of this.subscribedSessions) {
            this.sendCommand({ type: "SUBSCRIBE", sessionId });
          }

          resolve();
        };

        this.ws.onclose = (event) => {
          this.stopHeartbeat();

          if (event.wasClean) {
            this.setConnectionState("disconnected");
          } else {
            this.handleDisconnect();
          }
        };

        this.ws.onerror = (error) => {
          this.options.events.onError?.(new Error("WebSocket error"));
          if (this.connectionState === "connecting") {
            reject(new Error("Failed to connect to relay"));
          }
        };

        this.ws.onmessage = (event) => {
          this.handleMessage(event.data);
        };
      } catch (error) {
        this.setConnectionState("error");
        reject(error);
      }
    });
  }

  /**
   * Disconnect from the relay server
   */
  disconnect(): void {
    this.stopHeartbeat();
    this.stopReconnect();

    if (this.ws) {
      this.ws.close(1000, "Client disconnect");
      this.ws = null;
    }

    this.setConnectionState("disconnected");
    this.subscribedSessions.clear();
  }

  /**
   * Subscribe to a coding session
   */
  subscribeToSession(sessionId: string): void {
    this.subscribedSessions.add(sessionId);

    if (this.connectionState === "connected") {
      this.sendCommand({ type: "SUBSCRIBE", sessionId });
    }
  }

  /**
   * Unsubscribe from a coding session
   */
  unsubscribeFromSession(sessionId: string): void {
    this.subscribedSessions.delete(sessionId);

    if (this.connectionState === "connected") {
      this.sendCommand({ type: "UNSUBSCRIBE", sessionId });
    }
  }

  /**
   * Send a message to a coding session (encrypted)
   */
  async sendMessage(sessionId: string, message: SessionMessage): Promise<void> {
    if (this.connectionState !== "connected") {
      throw new Error("Not connected to relay");
    }

    const session = this.options.sessionManager.getState();
    if (!session) {
      throw new Error("No web session");
    }

    // Encrypt the message
    const plaintext = new TextEncoder().encode(JSON.stringify(message));
    const encrypted = this.options.sessionManager.encryptToBase64(plaintext);

    // Create envelope
    const envelope: RelayEnvelope = {
      type: "session",
      sessionId,
      senderId: `web:${session.id}`,
      timestamp: Date.now(),
      payload: encrypted,
    };

    this.ws?.send(JSON.stringify(envelope));
  }

  /**
   * Get current connection state
   */
  getConnectionState(): ConnectionState {
    return this.connectionState;
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    return this.connectionState === "connected";
  }

  private setConnectionState(state: ConnectionState): void {
    this.connectionState = state;
    this.options.events.onConnectionChange?.(state);
  }

  private handleMessage(data: string): void {
    try {
      const message = JSON.parse(data);

      // Handle relay commands
      if (message.type === "AUTH_SUCCESS") {
        return;
      }

      if (message.type === "AUTH_FAILURE") {
        this.options.events.onError?.(new Error("Authentication failed"));
        this.disconnect();
        return;
      }

      if (message.type === "PRESENCE") {
        this.options.events.onPresence?.(message.deviceId, message.status);
        return;
      }

      // Handle encrypted envelopes
      if (message.payload && message.sessionId) {
        this.handleEncryptedEnvelope(message as RelayEnvelope);
      }
    } catch (error) {
      this.options.events.onError?.(
        new Error(`Failed to parse message: ${error}`)
      );
    }
  }

  private handleEncryptedEnvelope(envelope: RelayEnvelope): void {
    try {
      // Decrypt the payload
      const decrypted = this.options.sessionManager.decryptFromBase64(
        envelope.payload
      );
      const message = JSON.parse(new TextDecoder().decode(decrypted));

      if (envelope.type === "session") {
        this.options.events.onMessage?.(envelope.sessionId, message);
      } else if (envelope.type === "control") {
        this.options.events.onControl?.(message);
      }
    } catch (error) {
      this.options.events.onError?.(
        new Error(`Failed to decrypt message: ${error}`)
      );
    }
  }

  private sendCommand(command: Record<string, unknown>): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(command));
    }
  }

  private handleDisconnect(): void {
    if (this.reconnectAttempts >= this.options.maxReconnectAttempts) {
      this.setConnectionState("error");
      this.options.events.onError?.(
        new Error("Max reconnect attempts reached")
      );
      return;
    }

    this.setConnectionState("reconnecting");
    this.reconnectAttempts++;

    const delay =
      this.options.reconnectDelay * 2 ** (this.reconnectAttempts - 1);
    this.reconnectTimeout = setTimeout(() => {
      this.connect().catch((error) => {
        this.options.events.onError?.(error);
      });
    }, delay);
  }

  private stopReconnect(): void {
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
    this.reconnectAttempts = 0;
  }

  private startHeartbeat(): void {
    this.heartbeatInterval = setInterval(() => {
      this.sendCommand({ type: "HEARTBEAT" });
    }, 30_000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }
}
