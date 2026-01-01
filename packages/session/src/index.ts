/**
 * @unbound/session
 *
 * Multi-device session management with encrypted fan-out broadcasting.
 */

export {
  createSessionManager,
  generateWebSessionKey,
  MultiDeviceSessionManager,
  type SessionManagerOptions,
} from "./manager.js";

export {
  createParticipantEncryption,
  ParticipantEncryption,
  type ParticipantEncryptionOptions,
} from "./participant.js";

export type {
  AddParticipantOptions,
  BroadcastResult,
  CreateSessionOptions,
  EncryptedParticipantMessage,
  MultiDeviceSession,
  ParticipantRole,
  SessionParticipant,
  SessionPermission,
  SessionState,
} from "./types.js";
