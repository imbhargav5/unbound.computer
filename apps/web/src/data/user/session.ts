"use server";

import { authActionClient } from "@/lib/safe-action";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/create-supabase-user-server-action-client";

export const refreshSessionAction = authActionClient.action(async () => {
  const supabaseClient = await createSupabaseUserServerActionClient();
  const { error } = await supabaseClient.auth.refreshSession();

  if (error) {
    throw new Error(error.message);
  }

  // Return void if successful
});
