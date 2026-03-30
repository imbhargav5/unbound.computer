"use server";

import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";

/**
 * Get all recent sessions for deck view, including worktree info.
 * Returns sessions across all repositories with full context for grouping.
 */
export async function getDeckSessions(limit = 200) {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("local_llm_conversations")
    .select(
      `
      *,
      repository:repositories(
        id, name, remote_url, default_branch, is_worktree,
        worktree_branch, parent_repository_id,
        parent:repositories!parent_repository_id(id, name)
      ),
      device:devices(id, name, device_type)
    `,
    )
    .eq("user_id", user.sub)
    .order("session_started_at", { ascending: false })
    .limit(limit);

  if (error) {
    throw error;
  }

  return data;
}

export type DeckSession = Awaited<ReturnType<typeof getDeckSessions>>[number];
