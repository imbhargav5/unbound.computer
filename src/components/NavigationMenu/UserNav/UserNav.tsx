// UserNav.tsx
import { Notifications } from "@/components/NavigationMenu/Notifications";
import { getIsAppAdmin } from "@/data/user/user";
import { getCachedUserProfile } from "@/rsc-data/user/user";
import { serverGetLoggedInUser } from "@/utils/server/serverGetLoggedInUser";

export async function UserNav() {
  const user = await serverGetLoggedInUser();
  const { email } = user;
  if (!email) {
    throw new Error("User email not found");
  }
  const [userProfile, isUserAppAdmin] = await Promise.all([
    getCachedUserProfile(),
    getIsAppAdmin(),
  ]);

  return (
    <div className="flex items-center space-x-4">
      <Notifications userId={user.id} />
    </div>
  );
}
