import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "database/types";
import { SESSION_LIMITS, SESSION_STATUS } from "./config";

type CodingSession = Database["public"]["Tables"]["coding_sessions"]["Row"];

export interface SessionValidationResult {
  valid: boolean;
  error?: string;
  code?: string;
}

/**
 * Validate session limits for a user
 */
export async function validateSessionLimits(
  supabase: SupabaseClient<Database>,
  userId: string,
  deviceId: string
): Promise<SessionValidationResult> {
  // Check user's active session count
  const { count: userSessionCount, error: userError } = await supabase
    .from("coding_sessions")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("status", SESSION_STATUS.ACTIVE);

  if (userError) {
    return { valid: false, error: userError.message, code: "DB_ERROR" };
  }

  if ((userSessionCount ?? 0) >= SESSION_LIMITS.MAX_SESSIONS_PER_USER) {
    return {
      valid: false,
      error: `Maximum concurrent sessions per user (${SESSION_LIMITS.MAX_SESSIONS_PER_USER}) reached`,
      code: "USER_LIMIT_EXCEEDED",
    };
  }

  // Check device's active session count
  const { count: deviceSessionCount, error: deviceError } = await supabase
    .from("coding_sessions")
    .select("*", { count: "exact", head: true })
    .eq("device_id", deviceId)
    .eq("status", SESSION_STATUS.ACTIVE);

  if (deviceError) {
    return { valid: false, error: deviceError.message, code: "DB_ERROR" };
  }

  if ((deviceSessionCount ?? 0) >= SESSION_LIMITS.MAX_SESSIONS_PER_DEVICE) {
    return {
      valid: false,
      error: `Maximum concurrent sessions per device (${SESSION_LIMITS.MAX_SESSIONS_PER_DEVICE}) reached`,
      code: "DEVICE_LIMIT_EXCEEDED",
    };
  }

  return { valid: true };
}

/**
 * Validate that a device belongs to the user
 */
export async function validateDeviceOwnership(
  supabase: SupabaseClient<Database>,
  userId: string,
  deviceId: string
): Promise<SessionValidationResult> {
  const { data: device, error } = await supabase
    .from("devices")
    .select("id, is_active")
    .eq("id", deviceId)
    .eq("user_id", userId)
    .single();

  if (error || !device) {
    return {
      valid: false,
      error: "Device not found or not owned by user",
      code: "DEVICE_NOT_FOUND",
    };
  }

  if (!device.is_active) {
    return {
      valid: false,
      error: "Device is not active",
      code: "DEVICE_INACTIVE",
    };
  }

  return { valid: true };
}

/**
 * Validate that a repository belongs to the user
 */
export async function validateRepositoryOwnership(
  supabase: SupabaseClient<Database>,
  userId: string,
  repositoryId: string
): Promise<SessionValidationResult> {
  const { data: repo, error } = await supabase
    .from("repositories")
    .select("id, status")
    .eq("id", repositoryId)
    .eq("user_id", userId)
    .single();

  if (error || !repo) {
    return {
      valid: false,
      error: "Repository not found or not owned by user",
      code: "REPOSITORY_NOT_FOUND",
    };
  }

  if (repo.status !== "active") {
    return {
      valid: false,
      error: "Repository is archived",
      code: "REPOSITORY_ARCHIVED",
    };
  }

  return { valid: true };
}

/**
 * Validate session ownership and state for operations
 */
export async function validateSessionForOperation(
  supabase: SupabaseClient<Database>,
  userId: string,
  sessionId: string,
  allowedStatuses: string[]
): Promise<{
  valid: boolean;
  session?: CodingSession;
  error?: string;
  code?: string;
}> {
  const { data: session, error } = await supabase
    .from("coding_sessions")
    .select("*")
    .eq("id", sessionId)
    .eq("user_id", userId)
    .single();

  if (error || !session) {
    return {
      valid: false,
      error: "Session not found or not owned by user",
      code: "SESSION_NOT_FOUND",
    };
  }

  if (!allowedStatuses.includes(session.status)) {
    return {
      valid: false,
      error: `Session cannot be modified in ${session.status} state`,
      code: "INVALID_SESSION_STATE",
    };
  }

  return { valid: true, session };
}

/**
 * Check if session has exceeded idle timeout
 */
export function isSessionIdle(session: CodingSession): boolean {
  if (!session.last_heartbeat_at) return false;

  const lastHeartbeat = new Date(session.last_heartbeat_at);
  const idleTimeoutMs = SESSION_LIMITS.IDLE_TIMEOUT_HOURS * 60 * 60 * 1000;
  return Date.now() - lastHeartbeat.getTime() > idleTimeoutMs;
}

/**
 * Check if session has exceeded maximum duration
 */
export function isSessionExpired(session: CodingSession): boolean {
  const startedAt = new Date(session.session_started_at);
  const maxDurationMs =
    SESSION_LIMITS.MAX_SESSION_DURATION_HOURS * 60 * 60 * 1000;
  return Date.now() - startedAt.getTime() > maxDurationMs;
}
