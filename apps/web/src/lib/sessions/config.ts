/**
 * Session limits and policies configuration
 */
export const SESSION_LIMITS = {
  /** Maximum concurrent sessions per user */
  MAX_SESSIONS_PER_USER: 3,
  /** Maximum concurrent sessions per device */
  MAX_SESSIONS_PER_DEVICE: 2,
  /** Maximum session duration in hours */
  MAX_SESSION_DURATION_HOURS: 24,
  /** Idle timeout in hours */
  IDLE_TIMEOUT_HOURS: 2,
} as const;

/**
 * Session status enum matching database
 */
export const SESSION_STATUS = {
  ACTIVE: "active",
  PAUSED: "paused",
  ENDED: "ended",
} as const;

export type SessionStatus =
  (typeof SESSION_STATUS)[keyof typeof SESSION_STATUS];

/**
 * Session command types for relay communication
 */
export const SESSION_COMMANDS = {
  PAUSE: "session:pause",
  RESUME: "session:resume",
  TERMINATE: "session:terminate",
  COMPLETE: "session:complete",
} as const;

export type SessionCommand =
  (typeof SESSION_COMMANDS)[keyof typeof SESSION_COMMANDS];
