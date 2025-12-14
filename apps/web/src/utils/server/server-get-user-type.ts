"use server";
import { cache } from "react";
import { userRoles } from "@/utils/user-types";
import { isSupabaseUserClaimAppAdmin } from "../is-supabase-user-app-admin";
import { serverGetLoggedInUserClaims } from "./server-get-logged-in-user";

// make sure to return one of UserRoles
export const serverGetUserType = cache(async () => {
  try {
    const claims = await serverGetLoggedInUserClaims();
    const isAdmin = isSupabaseUserClaimAppAdmin(claims);
    if (isAdmin) {
      return userRoles.ADMIN;
    }
    return userRoles.USER;
  } catch (error) {
    return userRoles.ANON;
  }
});
