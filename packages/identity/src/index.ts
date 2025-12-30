// Types

// Device identity
export {
  createDeviceIdentity,
  detectDeviceType,
  generateDeviceId,
  generateFingerprint,
  getDefaultDeviceName,
  serializeDeviceIdentity,
  validateDeviceInfo,
} from "./device.js";
// Session identity
export {
  createSessionIdentity,
  deserializeSessionIdentity,
  extendSession,
  generateSessionId,
  isSessionExpired,
  serializeSessionIdentity,
  validateSessionInfo,
} from "./session.js";
export type {
  DeviceIdentity,
  DeviceInfo,
  DeviceType,
  SessionIdentity,
  SessionInfo,
} from "./types.js";
export {
  DeviceInfoSchema,
  DeviceTypeSchema,
  SessionInfoSchema,
} from "./types.js";
