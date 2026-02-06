import { Home, Play, Terminal } from "lucide-react";
import { Suspense } from "react";
import { Link } from "@/components/intl-link";
import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import { getActiveCodingSessions } from "@/data/user/coding-sessions";

async function ActiveSessionItems() {
  let sessions: Awaited<ReturnType<typeof getActiveCodingSessions>> = [];

  try {
    sessions = await getActiveCodingSessions();
  } catch {
    // User may not be logged in yet during SSR
    return null;
  }

  if (sessions.length === 0) {
    return null;
  }

  return (
    <>
      {sessions.map((session) => (
        <SidebarMenuItem key={session.id}>
          <SidebarMenuButton asChild>
            <Link href={`/session/${session.id}`}>
              <Terminal className="h-4 w-4" />
              <span className="truncate">
                {session.repository?.name ?? "Session"}
              </span>
            </Link>
          </SidebarMenuButton>
          <SidebarMenuBadge>
            <Play className="h-3 w-3 text-green-500" />
          </SidebarMenuBadge>
        </SidebarMenuItem>
      ))}
    </>
  );
}

export async function SidebarSessionsNav() {
  return (
    <SidebarGroup className="group-data-[collapsible=icon]:hidden">
      <SidebarGroupLabel>Platform</SidebarGroupLabel>
      <SidebarMenu>
        <SidebarMenuItem>
          <SidebarMenuButton asChild>
            <Link href="/user">
              <Home className="h-4 w-4" />
              Dashboard
            </Link>
          </SidebarMenuButton>
        </SidebarMenuItem>
        <Suspense>
          <ActiveSessionItems />
        </Suspense>
      </SidebarMenu>
    </SidebarGroup>
  );
}
