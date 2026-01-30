import { z } from "zod";

/**
 * Device roles in a multi-device session
 * - executor: The device running Claude (Mac)
 * - controller: The trust root device that can control sessions (iOS)
 * - viewer: Temporary viewer of session output (Web)
 */
export const DeviceRoleSchema = z.enum(["executor", "controller", "viewer"]);
export type DeviceRole = z.infer<typeof DeviceRoleSchema>;

/**
 * Session permissions for devices
 */
export const SessionPermissionSchema = z.enum([
  "view_only",
  "interact",
  "full_control",
]);
export type SessionPermission = z.infer<typeof SessionPermissionSchema>;

/**
 * JOIN_SESSION command - join a session with a specific role
 */
export const JoinSessionCommandSchema = z.object({
  type: z.literal("JOIN_SESSION"),
  sessionId: z.string().uuid(),
  role: DeviceRoleSchema,
  permission: SessionPermissionSchema.optional(),
});

export type JoinSessionCommand = z.infer<typeof JoinSessionCommandSchema>;

/**
 * LEAVE_SESSION command - leave a session
 */
export const LeaveSessionCommandSchema = z.object({
  type: z.literal("LEAVE_SESSION"),
  sessionId: z.string().uuid(),
});

export type LeaveSessionCommand = z.infer<typeof LeaveSessionCommandSchema>;

/**
 * Session participant information
 */
export interface SessionParticipant {
  deviceId: string;
  deviceName?: string;
  role: DeviceRole;
  permission: SessionPermission;
  joinedAt: Date;
  isActive: boolean;
}

/**
 * Session state with role tracking
 */
export interface SessionState {
  sessionId: string;
  executorDeviceId?: string;
  controllerDeviceIds: Set<string>;
  viewerDeviceIds: Set<string>;
  participants: Map<string, SessionParticipant>;
  createdAt: Date;
}
