/**
 * Multi-Device Session Types
 *
 * Types for managing sessions with multiple participants (devices/viewers).
 */

/**
 * Session participant roles
 */
export type ParticipantRole = "host" | "controller" | "viewer";

/**
 * Permission levels for session participants
 */
export type SessionPermission = "view_only" | "interact" | "full_control";

/**
 * Session states
 */
export type SessionState = "pending" | "active" | "paused" | "ended";

/**
 * A participant in a multi-device session
 */
export interface SessionParticipant {
  /** Participant's device ID */
  deviceId: string;
  /** Participant's device public key (base64) */
  devicePublicKey: string;
  /** Role in the session */
  role: ParticipantRole;
  /** Permission level */
  permission: SessionPermission;
  /** Session-specific encryption key for this participant */
  sessionKey?: Uint8Array;
  /** When the participant joined */
  joinedAt: Date;
  /** Whether the participant is currently active */
  isActive: boolean;
}

/**
 * A multi-device session
 */
export interface MultiDeviceSession {
  /** Unique session ID */
  id: string;
  /** Device ID of the session host (executor) */
  hostDeviceId: string;
  /** Current session state */
  state: SessionState;
  /** Session participants */
  participants: Map<string, SessionParticipant>;
  /** When the session was created */
  createdAt: Date;
  /** When the session will expire */
  expiresAt?: Date;
  /** Session metadata */
  metadata?: Record<string, unknown>;
}

/**
 * Options for creating a multi-device session
 */
export interface CreateSessionOptions {
  /** Session ID (generated if not provided) */
  sessionId?: string;
  /** Host device ID */
  hostDeviceId: string;
  /** Host device public key (base64) */
  hostPublicKey: string;
  /** Session duration in milliseconds */
  durationMs?: number;
  /** Session metadata */
  metadata?: Record<string, unknown>;
}

/**
 * Options for adding a participant to a session
 */
export interface AddParticipantOptions {
  /** Participant's device ID */
  deviceId: string;
  /** Participant's device public key (base64) */
  devicePublicKey: string;
  /** Role in the session */
  role: ParticipantRole;
  /** Permission level (defaults to view_only) */
  permission?: SessionPermission;
}

/**
 * Encrypted message for a specific participant
 */
export interface EncryptedParticipantMessage {
  /** Target participant's device ID */
  targetDeviceId: string;
  /** Encrypted payload (base64) */
  payload: string;
  /** Nonce used for encryption (base64) */
  nonce: string;
}

/**
 * Broadcast result with encrypted messages for all participants
 */
export interface BroadcastResult {
  /** Session ID */
  sessionId: string;
  /** Encrypted messages keyed by device ID */
  messages: Map<string, EncryptedParticipantMessage>;
  /** Device IDs that failed encryption */
  failed: string[];
}
