"use server";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/createSupabaseUserServerComponentClient";
import { userRoles } from "@/utils/userTypes";
import { cache } from "react";
import { isSupabaseUserAppAdmin } from "../isSupabaseUserAppAdmin";

// make sure to return one of UserRoles
export const serverGetUserType = cache(async () => {
  const supabase = await createSupabaseUserServerComponentClient();
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError) {
    throw userError;
  }

  if (!user) {
    return userRoles.ANON;
  }

  if (isSupabaseUserAppAdmin(user)) {
    return userRoles.ADMIN;
  }

  return userRoles.USER;
});
