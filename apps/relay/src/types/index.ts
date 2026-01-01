// Auth types
export type { AuthContext, AuthMessage, AuthResult } from "./auth.js";
export {
  AuthMessageSchema,
  AuthResultSchema,
  createAuthFailure,
  createAuthSuccess,
} from "./auth.js";

// Command types
export type {
  HeartbeatCommand,
  JoinSessionCommand,
  LeaveSessionCommand,
  RegisterRoleCommand,
  RelayCommand,
  SubscribeCommand,
  UnsubscribeCommand,
} from "./commands.js";
export {
  HeartbeatCommandSchema,
  JoinSessionCommandSchema,
  LeaveSessionCommandSchema,
  parseRelayCommand,
  RegisterRoleCommandSchema,
  RelayCommandSchema,
  SubscribeCommandSchema,
  UnsubscribeCommandSchema,
} from "./commands.js";
// Event types
export type {
  DeliveryFailedEvent,
  ErrorEvent,
  HeartbeatAckEvent,
  MemberJoinedEvent,
  MemberLeftEvent,
  RelayEvent,
  SubscribedEvent,
  UnsubscribedEvent,
} from "./events.js";
export {
  createDeliveryFailedEvent,
  createErrorEvent,
  createHeartbeatAckEvent,
  createMemberJoinedEvent,
  createMemberLeftEvent,
  createSubscribedEvent,
  createUnsubscribedEvent,
  DeliveryFailedEventSchema,
  ErrorEventSchema,
  HeartbeatAckEventSchema,
  MemberJoinedEventSchema,
  MemberLeftEventSchema,
  RelayEventSchema,
  SubscribedEventSchema,
  UnsubscribedEventSchema,
} from "./events.js";
// Role types
export type {
  DeviceRole,
  RoleAnnouncementEvent,
  SessionParticipant,
  SessionPermission,
  SessionState,
} from "./roles.js";
export {
  createRoleAnnouncementEvent,
  DeviceRoleSchema,
  RoleAnnouncementEventSchema,
  SessionPermissionSchema,
} from "./roles.js";
