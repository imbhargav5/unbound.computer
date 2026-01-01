/**
 * Relay client types for web session viewing
 */

import type { RemoteControlAck, StreamChunk } from "@unbound/protocol";

/**
 * Connection state for the WebSocket relay client
 */
export type ConnectionState =
  | "disconnected"
  | "connecting"
  | "authenticating"
  | "authenticated"
  | "error";

/**
 * Relay events that the client can receive
 */
export interface RelayEvents {
  onConnectionStateChange: (state: ConnectionState) => void;
  onStreamChunk: (chunk: StreamChunk) => void;
  onRemoteControlAck: (ack: RemoteControlAck) => void;
  onMemberJoined: (data: MemberJoinedData) => void;
  onMemberLeft: (data: MemberLeftData) => void;
  onSessionEnded: (sessionId: string) => void;
  onError: (error: RelayError) => void;
}

/**
 * Member joined event data
 */
export interface MemberJoinedData {
  sessionId: string;
  deviceId: string;
  deviceName?: string;
  role?: string;
  permission?: string;
}

/**
 * Member left event data
 */
export interface MemberLeftData {
  sessionId: string;
  deviceId: string;
  role?: string;
}

/**
 * Relay error types
 */
export interface RelayError {
  code: string;
  message: string;
  recoverable: boolean;
}

/**
 * Session participant with role info
 */
export interface SessionParticipant {
  deviceId: string;
  deviceName?: string;
  role?: string;
  permission?: string;
}

/**
 * Options for creating a WebRelayClient
 */
export interface WebRelayClientOptions {
  relayUrl: string;
  sessionId: string;
  viewerId: string;
  authToken: string;
  permission?: "view_only" | "interact" | "full_control";
  onConnectionStateChange?: (state: ConnectionState) => void;
  onStreamChunk?: (chunk: StreamChunk) => void;
  onRemoteControlAck?: (ack: RemoteControlAck) => void;
  onMemberJoined?: (data: MemberJoinedData) => void;
  onMemberLeft?: (data: MemberLeftData) => void;
  onSessionEnded?: (sessionId: string) => void;
  onError?: (error: RelayError) => void;
  reconnectInterval?: number;
  maxReconnectAttempts?: number;
  heartbeatInterval?: number;
}

/**
 * Parsed message from the relay
 */
export type RelayMessage =
  | { type: "AUTH_SUCCESS"; deviceId: string }
  | { type: "AUTH_FAILED"; reason: string }
  | { type: "SUBSCRIBED"; sessionId: string; members: SessionParticipant[] }
  | { type: "UNSUBSCRIBED"; sessionId: string }
  | {
      type: "MEMBER_JOINED";
      sessionId: string;
      deviceId: string;
      deviceName?: string;
      role?: string;
      permission?: string;
    }
  | { type: "MEMBER_LEFT"; sessionId: string; deviceId: string; role?: string }
  | { type: "STREAM_CHUNK"; chunk: StreamChunk }
  | { type: "REMOTE_CONTROL_ACK"; ack: RemoteControlAck }
  | { type: "HEARTBEAT_ACK"; timestamp: number }
  | { type: "ERROR"; code: string; message: string }
  | { type: "DELIVERY_FAILED"; reason: string; sessionId?: string }
  | { type: "UNKNOWN"; data: unknown };
