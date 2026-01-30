"use server";
import { cache } from "react";
import { userRoles } from "@/utils/user-types";
import {
  isSupabaseUserAppAdmin,
  isSupabaseUserClaimAppAdmin,
} from "../is-supabase-user-app-admin";
import {
  serverGetLoggedInUserClaims,
  serverGetLoggedInUserVerified,
} from "./server-get-logged-in-user";

// make sure to return one of UserRoles
export const serverGetClaimType = cache(async () => {
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

// make sure to return one of UserRoles
// This actually makes a call to the database to get the user session
// and ensures that user is actually admin.
export const serverGetUserType = cache(async () => {
  try {
    const user = await serverGetLoggedInUserVerified();
    const isAdmin = isSupabaseUserAppAdmin(user);
    if (isAdmin) {
      return userRoles.ADMIN;
    }
    return userRoles.USER;
  } catch (error) {
    return userRoles.ANON;
  }
});
