// Types

export type {
  Ack,
  ControlMessage,
  Error,
  Heartbeat,
  Ready,
  Typing,
  Waiting,
} from "./control.js";
// Control messages
export {
  AckSchema,
  ControlMessageSchema,
  ErrorSchema,
  HeartbeatSchema,
  parseControlMessage,
  ReadySchema,
  TypingSchema,
  validateControlMessage,
  WaitingSchema,
} from "./control.js";
export type { RelayEnvelope } from "./envelope.js";
// Envelope
export {
  createEnvelope,
  MessageTypeSchema,
  parseEnvelope,
  RelayEnvelopeSchema,
  validateEnvelope,
} from "./envelope.js";
// Multi-device protocol extensions
export type {
  CreateRemoteControlOptions,
  CreateStreamChunkOptions,
  CreateViewerKeyExchangeOptions,
  DeviceRole,
  MultiDeviceMessage,
  RemoteControl,
  RemoteControlAck,
  RemoteControlAction,
  RoleAnnouncement,
  SessionPermission,
  StreamChunk,
  StreamContentType,
  ViewerKeyExchange,
  ViewerKeyExchangeResponse,
  ViewerType,
} from "./multidevice.js";
export {
  createRemoteControl,
  createRemoteControlAck,
  createRoleAnnouncement,
  createStreamChunk,
  createViewerKeyExchange,
  DeviceRoleSchema,
  MultiDeviceMessageSchema,
  parseMultiDeviceMessage,
  RemoteControlAckSchema,
  RemoteControlActionSchema,
  RemoteControlSchema,
  RoleAnnouncementSchema,
  SessionPermissionSchema,
  StreamChunkSchema,
  StreamContentTypeSchema,
  ViewerKeyExchangeResponseSchema,
  ViewerKeyExchangeSchema,
  ViewerTypeSchema,
  validateMultiDeviceMessage,
} from "./multidevice.js";
// Pairing options type
export type {
  CreatePairingResponseOptions,
  PairingConfirmation,
  PairingMessage,
  PairingRequest,
  PairingResponse,
} from "./pairing.js";
// Pairing messages
export {
  createPairingConfirmation,
  createPairingRequest,
  createPairingResponse,
  PairingConfirmationSchema,
  PairingMessageSchema,
  PairingRequestSchema,
  PairingResponseSchema,
  parsePairingMessage,
  validatePairingMessage,
} from "./pairing.js";
export type { PresenceMessage, PresenceStatus } from "./presence.js";
// Presence messages
export {
  createPresenceMessage,
  PresenceMessageSchema,
  PresenceStatusSchema,
  parsePresenceMessage,
  validatePresenceMessage,
} from "./presence.js";
export type {
  EndSession,
  Input,
  Output,
  PauseSession,
  ResumeSession,
  SessionCommand,
  StartSession,
} from "./session.js";
// Session commands
export {
  EndSessionSchema,
  InputSchema,
  OutputSchema,
  PauseSessionSchema,
  parseSessionCommand,
  ResumeSessionSchema,
  SessionCommandSchema,
  StartSessionSchema,
  validateSessionCommand,
} from "./session.js";
export type {
  ControlAction,
  InputType,
  MessageType,
  PresenceStatus as PresenceStatusType,
  SessionCommandType,
} from "./types.js";
