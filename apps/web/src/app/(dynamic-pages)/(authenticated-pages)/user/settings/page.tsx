import { Suspense } from "react";
import { getUserProfile } from "@/data/user/user";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import { AccountSettings } from "./account-settings";

async function AccountSettingsContent() {
  const user = await serverGetLoggedInUserClaims();
  const userProfile = await getUserProfile(user.sub);
  return <AccountSettings userEmail={user.email} userProfile={userProfile} />;
}

export default async function AccountSettingsPage() {
  return (
    <Suspense>
      <AccountSettingsContent />
    </Suspense>
  );
}
