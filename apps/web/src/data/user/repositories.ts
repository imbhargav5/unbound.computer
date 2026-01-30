"use server";

import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";

/**
 * Get all repositories for the current user (excluding worktrees).
 * Includes nested worktrees and active sessions.
 */
export async function getUserRepositories() {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("repositories")
    .select(
      `
      *,
      device:devices(id, name, device_type),
      worktrees:repositories!parent_repository_id(
        id, name, local_path, worktree_branch, status
      ),
      active_sessions:agent_coding_sessions!repository_id(
        id, status, session_started_at, current_branch
      )
    `
    )
    .eq("user_id", user.sub)
    .eq("is_worktree", false)
    .eq("status", "active")
    .order("updated_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Get repositories for a specific device.
 */
export async function getRepositoriesByDevice(deviceId: string) {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("repositories")
    .select(
      `
      *,
      worktrees:repositories!parent_repository_id(
        id, name, local_path, worktree_branch, status
      ),
      active_sessions:agent_coding_sessions!repository_id(
        id, status, session_started_at, current_branch
      )
    `
    )
    .eq("user_id", user.sub)
    .eq("device_id", deviceId)
    .eq("is_worktree", false)
    .eq("status", "active")
    .order("updated_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Get a single repository with its worktrees and sessions.
 */
export async function getRepositoryWithWorktrees(repositoryId: string) {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("repositories")
    .select(
      `
      *,
      device:devices(id, name, device_type),
      worktrees:repositories!parent_repository_id(
        id, name, local_path, worktree_branch, status,
        active_sessions:agent_coding_sessions!repository_id(
          id, status, session_started_at
        )
      ),
      active_sessions:agent_coding_sessions!repository_id(
        id, status, session_started_at, current_branch
      )
    `
    )
    .eq("id", repositoryId)
    .eq("user_id", user.sub)
    .single();

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Get repository count for the current user.
 */
export async function getRepositoryCount() {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { count, error } = await supabaseClient
    .from("repositories")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.sub)
    .eq("is_worktree", false)
    .eq("status", "active");

  if (error) {
    throw error;
  }

  return count ?? 0;
}
