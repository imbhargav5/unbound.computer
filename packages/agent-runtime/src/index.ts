// Types

// Encryption
export type { EncryptedSessionMessage } from "./encryption.js";
export {
  createEncryptionManager,
  createSessionEncryption,
  EncryptionManager,
  SessionEncryption,
} from "./encryption.js";
// Session manager
export type { SessionManagerEvents } from "./manager.js";
export { createSessionManager, SessionManager } from "./manager.js";
// Process management
export type { ProcessEvents } from "./process.js";
export {
  ClaudeProcess,
  createClaudeProcess,
  isClaudeInstalled,
} from "./process.js";
// Message queue
export type { QueueConfig, QueueEvents } from "./queue.js";
export { createMessageQueue, MessageQueue } from "./queue.js";
// Session
export type { SessionEvents } from "./session.js";
export { createSession, createSessionWithId, Session } from "./session.js";
export type {
  MessageType,
  ProcessInfo,
  SessionConfig,
  SessionEvent,
  SessionEventType,
  SessionManagerConfig,
  SessionMessage,
  SessionMetadata,
  SessionResult,
  SessionState,
  SpawnOptions,
  StateChangeData,
  StreamChunk,
} from "./types.js";
export {
  DEFAULT_SESSION_MANAGER_CONFIG,
  MessageType as MessageTypeEnum,
  SessionConfigSchema,
  SessionEventType as SessionEventTypeEnum,
  SessionMessageSchema,
  SessionState as SessionStateEnum,
  SessionStateSchema,
  STATE_TRANSITIONS,
} from "./types.js";
