"use server";
import { getIsAppAdmin } from "../user/user";

export const ensureAppAdmin = async () => {
  const isAppAdmin = await getIsAppAdmin();

  if (!isAppAdmin) {
    throw new Error("User is not an app admin");
  }

  return true;
};

export async function isLoggedInUserAppAdmin(): Promise<boolean> {
  const isAppAdmin = await getIsAppAdmin();

  return isAppAdmin;
}
