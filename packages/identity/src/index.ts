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
// Trust relationships
export type {
  CreateTrustRelationshipOptions,
  DeviceRole,
  TrustRelationship,
  TrustRelationshipInfo,
  TrustStatus,
} from "./trust.js";
export {
  activateTrust,
  createTrustRelationship,
  DeviceRoleSchema,
  deserializeTrustRelationship,
  isTrustValid,
  revokeTrust,
  serializeTrustRelationship,
  TrustRelationshipInfoSchema,
  TrustStatusSchema,
  validateTrustRelationshipInfo,
} from "./trust.js";
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
