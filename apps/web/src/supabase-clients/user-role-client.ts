"use server";

import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { supabaseAnonClient } from "@/supabase-clients/anon/supabase-anon-client";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/create-supabase-user-server-action-client";
import { serverGetClaimType } from "@/utils/server/server-get-user-type";
import { userRoles } from "@/utils/user-types";

export async function supabaseClientBasedOnUserRole() {
  const userRoleType = await serverGetClaimType();

  const supabaseClient = {
    [userRoles.ANON]: () => supabaseAnonClient,
    [userRoles.ADMIN]: () => supabaseAdminClient,
    [userRoles.USER]: async () => await createSupabaseUserServerActionClient(),
  }[userRoleType]();

  return supabaseClient;
}
