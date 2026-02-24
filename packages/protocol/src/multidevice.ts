import { z } from "zod";

/**
 * Device roles in the multi-device architecture
 */
export const DeviceRoleSchema = z.enum([
  "trust_root",
  "trusted_executor",
  "temporary_viewer",
]);
export type DeviceRole = z.infer<typeof DeviceRoleSchema>;

/**
 * Session permission levels
 */
export const SessionPermissionSchema = z.enum([
  "view_only",
  "interact",
  "full_control",
]);
export type SessionPermission = z.infer<typeof SessionPermissionSchema>;

// ========================================
// Role Announcement
// ========================================

/**
 * Role announcement - sent when a device registers its role
 */
export const RoleAnnouncementSchema = z.object({
  type: z.literal("ROLE_ANNOUNCEMENT"),
  deviceId: z.string().uuid(),
  role: DeviceRoleSchema,
  accountId: z.string().uuid(),
  capabilities: z
    .object({
      canExecute: z.boolean().optional(),
      canControl: z.boolean().optional(),
      canView: z.boolean().optional(),
    })
    .optional(),
  timestamp: z.number(),
});

export type RoleAnnouncement = z.infer<typeof RoleAnnouncementSchema>;

/**
 * Create a role announcement message
 */
export function createRoleAnnouncement(
  deviceId: string,
  role: DeviceRole,
  accountId: string,
  capabilities?: RoleAnnouncement["capabilities"]
): RoleAnnouncement {
  return {
    type: "ROLE_ANNOUNCEMENT",
    deviceId,
    role,
    accountId,
    capabilities,
    timestamp: Date.now(),
  };
}

// ========================================
// Streaming
// ========================================

/**
 * Content types for stream chunks
 */
export const StreamContentTypeSchema = z.enum([
  "text",
  "tool_use",
  "tool_result",
  "error",
  "system",
]);
export type StreamContentType = z.infer<typeof StreamContentTypeSchema>;

/**
 * Stream chunk - for streaming Claude output to viewers
 */
export const StreamChunkSchema = z.object({
  type: z.literal("STREAM_CHUNK"),
  sessionId: z.string().uuid(),
  sequenceNumber: z.number(),
  contentType: StreamContentTypeSchema,
  content: z.string(),
  isComplete: z.boolean(),
  timestamp: z.number(),
});

export type StreamChunk = z.infer<typeof StreamChunkSchema>;

/**
 * Options for creating a stream chunk
 */
export interface CreateStreamChunkOptions {
  content: string;
  contentType: StreamContentType;
  isComplete?: boolean;
  sequenceNumber: number;
  sessionId: string;
}

/**
 * Create a stream chunk message
 */
export function createStreamChunk(
  options: CreateStreamChunkOptions
): StreamChunk {
  return {
    type: "STREAM_CHUNK",
    sessionId: options.sessionId,
    sequenceNumber: options.sequenceNumber,
    contentType: options.contentType,
    content: options.content,
    isComplete: options.isComplete ?? false,
    timestamp: Date.now(),
  };
}

// ========================================
// Viewer Key Exchange
// ========================================

/**
 * Viewer types
 */
export const ViewerTypeSchema = z.enum(["web", "mobile", "desktop"]);
export type ViewerType = z.infer<typeof ViewerTypeSchema>;

/**
 * Viewer key exchange - sent when a viewer wants to join a session
 */
export const ViewerKeyExchangeSchema = z.object({
  type: z.literal("VIEWER_KEY_EXCHANGE"),
  viewerId: z.string().uuid(),
  viewerPublicKey: z.string(), // Base64-encoded public key
  viewerType: ViewerTypeSchema,
  sessionId: z.string().uuid(),
  timestamp: z.number(),
});

export type ViewerKeyExchange = z.infer<typeof ViewerKeyExchangeSchema>;

/**
 * Options for creating a viewer key exchange
 */
export interface CreateViewerKeyExchangeOptions {
  sessionId: string;
  viewerId: string;
  viewerPublicKey: string;
  viewerType: ViewerType;
}

/**
 * Create a viewer key exchange message
 */
export function createViewerKeyExchange(
  options: CreateViewerKeyExchangeOptions
): ViewerKeyExchange {
  return {
    type: "VIEWER_KEY_EXCHANGE",
    viewerId: options.viewerId,
    viewerPublicKey: options.viewerPublicKey,
    viewerType: options.viewerType,
    sessionId: options.sessionId,
    timestamp: Date.now(),
  };
}

/**
 * Viewer key exchange response - sent by executor with encrypted session key
 */
export const ViewerKeyExchangeResponseSchema = z.object({
  type: z.literal("VIEWER_KEY_EXCHANGE_RESPONSE"),
  viewerId: z.string().uuid(),
  sessionId: z.string().uuid(),
  encryptedSessionKey: z.string(), // Base64-encoded encrypted key
  executorPublicKey: z.string(), // Base64-encoded public key
  permission: SessionPermissionSchema,
  success: z.boolean(),
  error: z.string().optional(),
  timestamp: z.number(),
});

export type ViewerKeyExchangeResponse = z.infer<
  typeof ViewerKeyExchangeResponseSchema
>;

// ========================================
// Remote Control
// ========================================

/**
 * Remote control actions
 */
export const RemoteControlActionSchema = z.enum([
  "PAUSE",
  "STOP",
  "RESUME",
  "INPUT",
]);
export type RemoteControlAction = z.infer<typeof RemoteControlActionSchema>;

/**
 * Remote control message - sent by controller to executor
 */
export const RemoteControlSchema = z.object({
  type: z.literal("REMOTE_CONTROL"),
  action: RemoteControlActionSchema,
  sessionId: z.string().uuid(),
  requesterId: z.string().uuid(),
  /** Content for INPUT action */
  content: z.string().optional(),
  /** Force flag for STOP action */
  force: z.boolean().optional(),
  timestamp: z.number(),
});

export type RemoteControl = z.infer<typeof RemoteControlSchema>;

/**
 * Options for creating a remote control message
 */
export interface CreateRemoteControlOptions {
  action: RemoteControlAction;
  content?: string;
  force?: boolean;
  requesterId: string;
  sessionId: string;
}

/**
 * Create a remote control message
 */
export function createRemoteControl(
  options: CreateRemoteControlOptions
): RemoteControl {
  return {
    type: "REMOTE_CONTROL",
    action: options.action,
    sessionId: options.sessionId,
    requesterId: options.requesterId,
    content: options.content,
    force: options.force,
    timestamp: Date.now(),
  };
}

/**
 * Remote control acknowledgment
 */
export const RemoteControlAckSchema = z.object({
  type: z.literal("REMOTE_CONTROL_ACK"),
  action: RemoteControlActionSchema,
  sessionId: z.string().uuid(),
  success: z.boolean(),
  error: z.string().optional(),
  timestamp: z.number(),
});

export type RemoteControlAck = z.infer<typeof RemoteControlAckSchema>;

/**
 * Create a remote control acknowledgment
 */
export function createRemoteControlAck(
  action: RemoteControlAction,
  sessionId: string,
  success: boolean,
  error?: string
): RemoteControlAck {
  return {
    type: "REMOTE_CONTROL_ACK",
    action,
    sessionId,
    success,
    error,
    timestamp: Date.now(),
  };
}

// ========================================
// Union Types
// ========================================

/**
 * All multi-device message types
 */
export const MultiDeviceMessageSchema = z.discriminatedUnion("type", [
  RoleAnnouncementSchema,
  StreamChunkSchema,
  ViewerKeyExchangeSchema,
  ViewerKeyExchangeResponseSchema,
  RemoteControlSchema,
  RemoteControlAckSchema,
]);

export type MultiDeviceMessage = z.infer<typeof MultiDeviceMessageSchema>;

/**
 * Validate a multi-device message
 */
export function validateMultiDeviceMessage(data: unknown): MultiDeviceMessage {
  return MultiDeviceMessageSchema.parse(data);
}

/**
 * Safe parse a multi-device message
 */
export function parseMultiDeviceMessage(
  data: unknown
):
  | { success: true; data: MultiDeviceMessage }
  | { success: false; error: z.ZodError } {
  const result = MultiDeviceMessageSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error };
}
