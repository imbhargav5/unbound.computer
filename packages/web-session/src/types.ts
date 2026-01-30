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
  /** Device ID */
  id: string;
  /** Device name */
  name: string;
  /** Device type */
  deviceType: string;
  /** Device's public key (base64) */
  publicKey?: string;
}

/**
 * Web session client state
 */
export interface WebSession {
  /** Session ID from the server */
  id: string;
  /** Current state */
  state: WebSessionState;
  /** Ephemeral keypair for this session */
  ephemeralKeyPair: KeyPair;
  /** Session token for API authentication */
  sessionToken: string;
  /** When the session was created */
  createdAt: Date;
  /** When the session expires */
  expiresAt: Date;
  /** When the session will expire due to inactivity */
  idleExpiresAt?: Date;
  /** Last activity timestamp */
  lastActivityAt: Date;
  /** Decrypted session key (only available after authorization) */
  sessionKey?: Uint8Array;
  /** Permission level for this session */
  permission: WebSessionPermission;
  /** Device that authorized this session */
  authorizingDevice?: AuthorizingDevice;
  /** Maximum idle time in seconds */
  maxIdleSeconds: number;
  /** Session TTL in seconds */
  sessionTtlSeconds: number;
  /** Error message if state is 'error' */
  error?: string;
}

/**
 * Server response from session init
 */
export interface WebSessionInitResponse {
  sessionId: string;
  sessionToken: string;
  qrData: string;
  expiresAt: string;
}

/**
 * Server response from session status
 */
export interface WebSessionStatusResponse {
  id: string;
  status: "pending" | "active" | "expired" | "revoked" | "idle_timeout";
  createdAt: string;
  expiresAt: string;
  authorizedAt: string | null;
  encryptedSessionKey: string | null;
  responderPublicKey: string | null;
  permission: WebSessionPermission;
  maxIdleSeconds: number;
  sessionTtlSeconds: number;
  lastActivityAt: string | null;
  authorizingDevice: {
    id: string;
    name: string;
    deviceType: string;
    publicKey?: string;
  } | null;
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
  /** Polling interval for status checks (ms) */
  pollingInterval?: number;
  /** Maximum polling attempts */
  maxPollingAttempts?: number;
  /** Maximum idle time in seconds (default: 30 minutes) */
  maxIdleSeconds?: number;
  /** Session TTL in seconds (default: 24 hours) */
  sessionTtlSeconds?: number;
  /** Enable automatic idle timeout checking */
  enableIdleTimeout?: boolean;
  /** Callback when session is about to expire (called 1 min before) */
  onExpiryWarning?: () => void;
}

/**
 * Storage interface for web session keys
 */
export interface WebSessionStorage {
  /** Store session data */
  set(key: string, value: string): void;
  /** Get session data */
  get(key: string): string | null;
  /** Remove session data */
  remove(key: string): void;
  /** Clear all session data */
  clear(): void;
}
