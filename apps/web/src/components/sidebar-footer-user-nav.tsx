import {
  BadgeCheck,
  ChevronsUpDown,
  Code,
  FileQuestion,
  History,
  LogOut,
  Shield,
} from "lucide-react";
import { Suspense } from "react";
import { getCachedUserProfile } from "@/rsc-data/user/user";
import { getUserAvatarUrl } from "@/utils/helpers";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import { Link } from "./intl-link";
import { NotificationsDropdownMenuTrigger } from "./notifications-dropdown-menu-trigger";
import { ThemeToggleClient } from "./theme-toggle-client";
import { Avatar, AvatarFallback, AvatarImage } from "./ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { SidebarMenuButton, SidebarMenuItem } from "./ui/sidebar";
import { UnseenNotificationCounterBadge } from "./unseen-notification-counter-badge";

async function SidebarFooterUserNavContent() {
  const [profile, userClaims] = await Promise.all([
    getCachedUserProfile(),
    serverGetLoggedInUserClaims(),
  ]);
  const avatarImage = getUserAvatarUrl({
    email: userClaims.email,
    profileAvatarUrl: profile.avatar_url,
  });
  return (
    <SidebarMenuItem>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <SidebarMenuButton
            className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
            data-testid="sidebar-user-nav-avatar-button"
            size="lg"
          >
            <Avatar className="h-8 w-8 rounded-lg">
              <AvatarImage
                alt={profile.full_name ?? userClaims.email}
                src={avatarImage}
              />
              <AvatarFallback className="rounded-lg">CN</AvatarFallback>
            </Avatar>
            <div className="grid flex-1 text-left text-sm leading-tight">
              <span className="truncate font-semibold">
                {profile.full_name ?? userClaims.email}
              </span>
              <span className="truncate text-xs">{userClaims.email}</span>
            </div>
            <UnseenNotificationCounterBadge userClaims={userClaims} />
            <ChevronsUpDown className="ml-auto size-4" />
          </SidebarMenuButton>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          align="end"
          className="w-(--radix-dropdown-menu-trigger-width) min-w-56 rounded-lg"
          side="bottom"
          sideOffset={4}
        >
          <DropdownMenuLabel className="p-0 font-normal">
            <div className="flex items-center gap-2 px-1 py-1.5 text-left text-sm">
              <Avatar className="h-8 w-8 rounded-lg">
                <AvatarImage
                  alt={profile.full_name ?? userClaims.email}
                  src={avatarImage}
                />
                <AvatarFallback className="rounded-lg">CN</AvatarFallback>
              </Avatar>
              <div className="grid flex-1 text-left text-sm leading-tight">
                <span className="truncate font-semibold">
                  {profile.full_name ?? userClaims.email}
                </span>
                <span className="truncate text-xs">{userClaims.email}</span>
              </div>
            </div>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuGroup>
            <NotificationsDropdownMenuTrigger userClaims={userClaims} />
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuGroup>
            <DropdownMenuItem asChild>
              <Link href="/user/settings">
                <BadgeCheck />
                Account Settings
              </Link>
            </DropdownMenuItem>
            <DropdownMenuItem asChild>
              <Link href="/user/settings/security">
                <Shield />
                Security Settings
              </Link>
            </DropdownMenuItem>
            <DropdownMenuItem asChild>
              <Link href="/user/settings/developer">
                <Code />
                Developer Settings
              </Link>
            </DropdownMenuItem>
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <DropdownMenuGroup>
            <DropdownMenuItem asChild>
              <Link href="/feedback">
                <FileQuestion />
                Feedback
              </Link>
            </DropdownMenuItem>
            <DropdownMenuItem asChild>
              <Link href="/changelog">
                <History />
                Changelog
              </Link>
            </DropdownMenuItem>
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <Suspense>
            <ThemeToggleClient />
          </Suspense>
          <DropdownMenuSeparator />
          <DropdownMenuItem asChild>
            <Link href="/logout">
              <LogOut />
              Log out
            </Link>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </SidebarMenuItem>
  );
}

export async function SidebarFooterUserNav() {
  return (
    <Suspense>
      <SidebarFooterUserNavContent />
    </Suspense>
  );
}
