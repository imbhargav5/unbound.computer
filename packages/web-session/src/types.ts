import type { KeyPair } from "@unbound/crypto";

/**
 * Web session states
 */
export type WebSessionState =
  | "idle"
  | "waiting_for_auth"
  | "authorized"
  | "expired"
  | "error";

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
  /** Decrypted session key (only available after authorization) */
  sessionKey?: Uint8Array;
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
  status: "pending" | "active" | "expired" | "revoked";
  createdAt: string;
  expiresAt: string;
  authorizedAt: string | null;
  encryptedSessionKey: string | null;
  responderPublicKey: string | null;
  authorizingDevice: {
    id: string;
    name: string;
    deviceType: string;
  } | null;
}

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
