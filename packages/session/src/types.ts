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
  /** Whether the participant is currently active */
  isActive: boolean;
  /** When the participant joined */
  joinedAt: Date;
  /** Permission level */
  permission: SessionPermission;
  /** Role in the session */
  role: ParticipantRole;
  /** Session-specific encryption key for this participant */
  sessionKey?: Uint8Array;
}

/**
 * A multi-device session
 */
export interface MultiDeviceSession {
  /** When the session was created */
  createdAt: Date;
  /** When the session will expire */
  expiresAt?: Date;
  /** Device ID of the session host (executor) */
  hostDeviceId: string;
  /** Unique session ID */
  id: string;
  /** Session metadata */
  metadata?: Record<string, unknown>;
  /** Session participants */
  participants: Map<string, SessionParticipant>;
  /** Current session state */
  state: SessionState;
}

/**
 * Options for creating a multi-device session
 */
export interface CreateSessionOptions {
  /** Session duration in milliseconds */
  durationMs?: number;
  /** Host device ID */
  hostDeviceId: string;
  /** Host device public key (base64) */
  hostPublicKey: string;
  /** Session metadata */
  metadata?: Record<string, unknown>;
  /** Session ID (generated if not provided) */
  sessionId?: string;
}

/**
 * Options for adding a participant to a session
 */
export interface AddParticipantOptions {
  /** Participant's device ID */
  deviceId: string;
  /** Participant's device public key (base64) */
  devicePublicKey: string;
  /** Permission level (defaults to view_only) */
  permission?: SessionPermission;
  /** Role in the session */
  role: ParticipantRole;
}

/**
 * Encrypted message for a specific participant
 */
export interface EncryptedParticipantMessage {
  /** Nonce used for encryption (base64) */
  nonce: string;
  /** Encrypted payload (base64) */
  payload: string;
  /** Target participant's device ID */
  targetDeviceId: string;
}

/**
 * Broadcast result with encrypted messages for all participants
 */
export interface BroadcastResult {
  /** Device IDs that failed encryption */
  failed: string[];
  /** Encrypted messages keyed by device ID */
  messages: Map<string, EncryptedParticipantMessage>;
  /** Session ID */
  sessionId: string;
}
