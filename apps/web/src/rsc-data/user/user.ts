"use server";

import { cache } from "react";
import { getUserProfile } from "@/data/user/user";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";

export const getCachedUserProfile = cache(async () => {
  const user = await serverGetLoggedInUserClaims();
  return await getUserProfile(user.sub);
});
