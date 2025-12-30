/**
 * Message types that flow through the relay
 */
export type MessageType =
  | "message"
  | "presence"
  | "pairing"
  | "control"
  | "session";

/**
 * Input types for session commands
 */
export type InputType = "prompt" | "confirmation" | "rejection";

/**
 * Presence status
 */
export type PresenceStatus = "online" | "offline" | "away";

/**
 * Control actions
 */
export type ControlAction = "TYPING" | "READY" | "WAITING" | "ERROR";

/**
 * Session commands
 */
export type SessionCommandType =
  | "START_SESSION"
  | "END_SESSION"
  | "PAUSE_SESSION"
  | "RESUME_SESSION"
  | "INPUT"
  | "OUTPUT";
