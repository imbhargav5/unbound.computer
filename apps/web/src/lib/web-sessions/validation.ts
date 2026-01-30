/**
 * Web Session validation utilities
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "database/types";
import { WEB_SESSION_STATUS } from "./types";

type ValidationResult =
  | { valid: true }
  | { valid: false; error: string; code: string };

/**
 * Validate that a device belongs to the user and is active
 */
export async function validateDeviceForWebAuth(
  supabase: SupabaseClient<Database>,
  userId: string,
  deviceId: string
): Promise<ValidationResult> {
  const { data: device, error } = await supabase
    .from("devices")
    .select("id, is_active")
    .eq("id", deviceId)
    .eq("user_id", userId)
    .single();

  if (error || !device) {
    return {
      valid: false,
      error: "Device not found or does not belong to user",
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
 * Validate that a web session is pending and not expired
 */
export async function validateWebSessionForAuth(
  supabase: SupabaseClient<Database>,
  userId: string,
  sessionId: string
): Promise<ValidationResult> {
  const { data: session, error } = await supabase
    .from("web_sessions")
    .select("id, status, expires_at")
    .eq("id", sessionId)
    .eq("user_id", userId)
    .single();

  if (error || !session) {
    return {
      valid: false,
      error: "Web session not found",
      code: "SESSION_NOT_FOUND",
    };
  }

  if (session.status !== WEB_SESSION_STATUS.PENDING) {
    return {
      valid: false,
      error: `Session is not in pending state (current: ${session.status})`,
      code: "SESSION_NOT_PENDING",
    };
  }

  const expiresAt = new Date(session.expires_at);
  if (expiresAt < new Date()) {
    return {
      valid: false,
      error: "Session has expired",
      code: "SESSION_EXPIRED",
    };
  }

  return { valid: true };
}

/**
 * Validate that a web session is active
 */
export async function validateActiveWebSession(
  supabase: SupabaseClient<Database>,
  userId: string,
  sessionId: string
): Promise<ValidationResult> {
  const { data: session, error } = await supabase
    .from("web_sessions")
    .select("id, status, expires_at")
    .eq("id", sessionId)
    .eq("user_id", userId)
    .single();

  if (error || !session) {
    return {
      valid: false,
      error: "Web session not found",
      code: "SESSION_NOT_FOUND",
    };
  }

  if (session.status !== WEB_SESSION_STATUS.ACTIVE) {
    return {
      valid: false,
      error: `Session is not active (current: ${session.status})`,
      code: "SESSION_NOT_ACTIVE",
    };
  }

  const expiresAt = new Date(session.expires_at);
  if (expiresAt < new Date()) {
    return {
      valid: false,
      error: "Session has expired",
      code: "SESSION_EXPIRED",
    };
  }

  return { valid: true };
}

/**
 * Rate limit check for web session creation
 * Prevents abuse by limiting pending sessions per user
 */
export async function checkWebSessionRateLimit(
  supabase: SupabaseClient<Database>,
  userId: string,
  maxPendingSessions = 5
): Promise<ValidationResult> {
  const { count, error } = await supabase
    .from("web_sessions")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("status", WEB_SESSION_STATUS.PENDING);

  if (error) {
    return {
      valid: false,
      error: "Failed to check rate limit",
      code: "RATE_LIMIT_ERROR",
    };
  }

  if (count !== null && count >= maxPendingSessions) {
    return {
      valid: false,
      error: `Too many pending sessions (max: ${maxPendingSessions})`,
      code: "TOO_MANY_PENDING_SESSIONS",
    };
  }

  return { valid: true };
}
