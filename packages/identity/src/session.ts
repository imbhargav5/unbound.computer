import type { SessionIdentity, SessionInfo } from "./types.js";
import { SessionInfoSchema } from "./types.js";

/**
 * Default session duration in milliseconds (24 hours)
 */
const DEFAULT_SESSION_DURATION = 24 * 60 * 60 * 1000;

/**
 * Generate a new session ID
 */
export function generateSessionId(): string {
  return crypto.randomUUID();
}

/**
 * Create a new session identity
 */
export function createSessionIdentity(
  deviceId: string,
  repositoryId?: string,
  durationMs = DEFAULT_SESSION_DURATION
): SessionIdentity {
  const now = new Date();
  return {
    id: generateSessionId(),
    deviceId,
    repositoryId,
    createdAt: now,
    expiresAt: new Date(now.getTime() + durationMs),
  };
}

/**
 * Check if a session has expired
 */
export function isSessionExpired(session: SessionIdentity): boolean {
  if (!session.expiresAt) {
    return false;
  }
  return new Date() > session.expiresAt;
}

/**
 * Extend a session's expiry time
 */
export function extendSession(
  session: SessionIdentity,
  durationMs = DEFAULT_SESSION_DURATION
): SessionIdentity {
  return {
    ...session,
    expiresAt: new Date(Date.now() + durationMs),
  };
}

/**
 * Serialize session identity to transportable format
 */
export function serializeSessionIdentity(
  session: SessionIdentity
): SessionInfo {
  return {
    id: session.id,
    deviceId: session.deviceId,
    repositoryId: session.repositoryId,
    createdAt: session.createdAt.toISOString(),
    expiresAt: session.expiresAt?.toISOString(),
  };
}

/**
 * Deserialize session info to session identity
 */
export function deserializeSessionIdentity(info: SessionInfo): SessionIdentity {
  return {
    id: info.id,
    deviceId: info.deviceId,
    repositoryId: info.repositoryId,
    createdAt: new Date(info.createdAt),
    expiresAt: info.expiresAt ? new Date(info.expiresAt) : undefined,
  };
}

/**
 * Validate session info
 */
export function validateSessionInfo(data: unknown): SessionInfo {
  return SessionInfoSchema.parse(data);
}
