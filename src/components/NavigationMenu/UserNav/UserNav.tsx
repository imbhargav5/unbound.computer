// UserNav.tsx
import { Notifications } from '@/components/NavigationMenu/Notifications';
import { ThemeToggle } from '@/components/ThemeToggle';
import { getIsAppAdmin, getUserProfile } from '@/data/user/user';
import { getUserAvatarUrl } from '@/utils/helpers';
import { serverGetLoggedInUser } from '@/utils/server/serverGetLoggedInUser';
import { UserNavDropdown } from './UserNavDropdown';

export async function UserNav() {
  const user = await serverGetLoggedInUser();
  const { email } = user;
  if (!email) {
    throw new Error('User email not found');
  }

  const userProfile = await getUserProfile(user.id);
  const isUserAppAdmin = await getIsAppAdmin();

  return (
    <div className="flex items-center space-x-4">
      <ThemeToggle />
      <Notifications userId={user.id} />
      <UserNavDropdown
        avatarUrl={getUserAvatarUrl({
          email,
          profileAvatarUrl: userProfile.avatar_url,
        })}
        userFullname={userProfile.full_name ?? `User ${email}`}
        userEmail={email}
        userId={user.id}
        isUserAppAdmin={isUserAppAdmin}
      />
    </div>
  );
}
