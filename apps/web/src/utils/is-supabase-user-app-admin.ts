import type { User } from "@supabase/supabase-js";
import type { UserClaimsSchemaType } from "./zod-schemas/user-claims-schema";

export function isSupabaseUserAppAdmin(user: User): boolean {
  if (user.app_metadata && "user_role" in user.app_metadata) {
    return user.app_metadata.user_role === "admin";
  }
  return false;
}

export function isSupabaseUserClaimAppAdmin(
  user: UserClaimsSchemaType
): boolean {
  if (user.app_metadata && "user_role" in user.app_metadata) {
    return user.app_metadata.user_role === "admin";
  }
  return false;
}
