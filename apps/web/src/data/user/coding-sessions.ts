"use server";

import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";

/**
 * Get all active coding sessions for the current user.
 */
export async function getActiveCodingSessions() {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("coding_sessions")
    .select(
      `
      *,
      repository:repositories(
        id, name, remote_url, is_worktree,
        parent:repositories!parent_repository_id(id, name)
      ),
      device:devices(id, name, device_type)
    `
    )
    .eq("user_id", user.sub)
    .eq("status", "active")
    .order("session_started_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Get coding session history for the current user.
 */
export async function getSessionHistory(limit = 20) {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("coding_sessions")
    .select(
      `
      *,
      repository:repositories(id, name, remote_url),
      device:devices(id, name, device_type)
    `
    )
    .eq("user_id", user.sub)
    .order("session_started_at", { ascending: false })
    .limit(limit);

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Get active session count for the current user.
 */
export async function getActiveSessionCount() {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { count, error } = await supabaseClient
    .from("coding_sessions")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.sub)
    .eq("status", "active");

  if (error) {
    throw error;
  }

  return count ?? 0;
}

/**
 * Get sessions for a specific repository.
 */
export async function getSessionsByRepository(repositoryId: string) {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("coding_sessions")
    .select(
      `
      *,
      device:devices(id, name, device_type)
    `
    )
    .eq("user_id", user.sub)
    .eq("repository_id", repositoryId)
    .order("session_started_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Get sessions for a specific device.
 */
export async function getSessionsByDevice(deviceId: string) {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("coding_sessions")
    .select(
      `
      *,
      repository:repositories(id, name, remote_url)
    `
    )
    .eq("user_id", user.sub)
    .eq("device_id", deviceId)
    .order("session_started_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data;
}
