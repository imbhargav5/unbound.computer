import type { KeyPair } from "@unbound/crypto";

/**
 * Web session states
 */
export type WebSessionState =
  | "idle"
  | "waiting_for_auth"
  | "authorized"
  | "expired"
  | "idle_timeout"
  | "error";

/**
 * Permission levels for web sessions
 */
export type WebSessionPermission = "view_only" | "interact" | "full_control";

/**
 * Information about the device that authorized the session
 */
export interface AuthorizingDevice {
  /** Device type */
  deviceType: string;
  /** Device ID */
  id: string;
  /** Device name */
  name: string;
  /** Device's public key (base64) */
  publicKey?: string;
}

/**
 * Web session client state
 */
export interface WebSession {
  /** Device that authorized this session */
  authorizingDevice?: AuthorizingDevice;
  /** When the session was created */
  createdAt: Date;
  /** Ephemeral keypair for this session */
  ephemeralKeyPair: KeyPair;
  /** Error message if state is 'error' */
  error?: string;
  /** When the session expires */
  expiresAt: Date;
  /** Session ID from the server */
  id: string;
  /** When the session will expire due to inactivity */
  idleExpiresAt?: Date;
  /** Last activity timestamp */
  lastActivityAt: Date;
  /** Maximum idle time in seconds */
  maxIdleSeconds: number;
  /** Permission level for this session */
  permission: WebSessionPermission;
  /** Decrypted session key (only available after authorization) */
  sessionKey?: Uint8Array;
  /** Session token for API authentication */
  sessionToken: string;
  /** Session TTL in seconds */
  sessionTtlSeconds: number;
  /** Current state */
  state: WebSessionState;
}

/**
 * Server response from session init
 */
export interface WebSessionInitResponse {
  expiresAt: string;
  qrData: string;
  sessionId: string;
  sessionToken: string;
}

/**
 * Server response from session status
 */
export interface WebSessionStatusResponse {
  authorizedAt: string | null;
  authorizingDevice: {
    id: string;
    name: string;
    deviceType: string;
    publicKey?: string;
  } | null;
  createdAt: string;
  encryptedSessionKey: string | null;
  expiresAt: string;
  id: string;
  lastActivityAt: string | null;
  maxIdleSeconds: number;
  permission: WebSessionPermission;
  responderPublicKey: string | null;
  sessionTtlSeconds: number;
  status: "pending" | "active" | "expired" | "revoked" | "idle_timeout";
}

/**
 * Default TTL values
 */
export const DEFAULT_MAX_IDLE_SECONDS = 1800; // 30 minutes
export const DEFAULT_SESSION_TTL_SECONDS = 86_400; // 24 hours

/**
 * Options for creating a web session
 */
export interface WebSessionOptions {
  /** API base URL */
  apiBaseUrl: string;
  /** Enable automatic idle timeout checking */
  enableIdleTimeout?: boolean;
  /** Maximum idle time in seconds (default: 30 minutes) */
  maxIdleSeconds?: number;
  /** Maximum polling attempts */
  maxPollingAttempts?: number;
  /** Callback when session is about to expire (called 1 min before) */
  onExpiryWarning?: () => void;
  /** Polling interval for status checks (ms) */
  pollingInterval?: number;
  /** Session TTL in seconds (default: 24 hours) */
  sessionTtlSeconds?: number;
}

/**
 * Storage interface for web session keys
 */
export interface WebSessionStorage {
  /** Clear all session data */
  clear(): void;
  /** Get session data */
  get(key: string): string | null;
  /** Remove session data */
  remove(key: string): void;
  /** Store session data */
  set(key: string, value: string): void;
}
