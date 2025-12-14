import { createClient } from "@supabase/supabase-js";
import type { Database } from "database/types";
import { Client } from "pg";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseSecretKey = process.env.SUPABASE_SECRET_KEY;
if (!(supabaseUrl && supabaseSecretKey)) {
  throw new Error("Supabase URL or secret key is not set");
}

export function createSupabaseTestAdminClient() {
  return createClient<Database>(supabaseUrl, supabaseSecretKey);
}

export function createPGClient() {
  return new Client({
    connectionString: process.env.SUPABASE_POSTGRES_DB_URL,
  });
}

export async function getUserIdByEmail(emailAddress: string) {
  // Find the user ID for the email
  const supabaseTestAdminClient = createSupabaseTestAdminClient();
  const userIdRes = await supabaseTestAdminClient
    .from("user_application_settings")
    .select("*")
    .eq("email_readonly", emailAddress)
    .single();

  const { data, error } = userIdRes;
  if (error) {
    throw error;
  }
  return data.id;
}

export async function getWorkspaceInvitationId(inviteeUserId: string) {
  // Find the user ID for the email
  const supabaseTestAdminClient = createSupabaseTestAdminClient();
  const userIdRes = await supabaseTestAdminClient
    .from("workspace_invitations")
    .select("*")
    .eq("inviter_user_id", inviteeUserId)
    .single();

  const { data, error } = userIdRes;
  if (error) {
    throw error;
  }
  return data.id;
}
