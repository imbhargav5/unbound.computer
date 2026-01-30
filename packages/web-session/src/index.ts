// Web Session Manager
export { WebSessionManager } from "./manager.js";
export type {
  ConnectionState,
  SessionMessage,
  WebRelayClientEvents,
  WebRelayClientOptions,
} from "./relay-client.js";
// Web Relay Client
export { WebRelayClient } from "./relay-client.js";

// Storage adapters
export {
  BrowserSessionStorage,
  MemoryStorage,
  STORAGE_KEYS,
} from "./storage.js";

// Types
export type {
  AuthorizingDevice,
  WebSession,
  WebSessionInitResponse,
  WebSessionOptions,
  WebSessionPermission,
  WebSessionState,
  WebSessionStatusResponse,
  WebSessionStorage,
} from "./types.js";

// Constants
export {
  DEFAULT_MAX_IDLE_SECONDS,
  DEFAULT_SESSION_TTL_SECONDS,
} from "./types.js";
