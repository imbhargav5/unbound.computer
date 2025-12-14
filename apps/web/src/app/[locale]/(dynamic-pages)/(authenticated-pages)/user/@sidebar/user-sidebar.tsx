// OrganizationSidebar.tsx (Server Component)

import { connection } from "next/server";
import { Suspense } from "react";
import { SidebarAdminPanelNav } from "@/components/sidebar-admin-panel-nav";
import { SwitcherAndToggle } from "@/components/sidebar-components/switcher-and-toggle";
import { SidebarFooterUserNav } from "@/components/sidebar-footer-user-nav";
import { SidebarPlatformNav } from "@/components/sidebar-platform-nav";
import { SidebarTipsNav } from "@/components/sidebar-tips-nav";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarRail,
} from "@/components/ui/sidebar";
import {
  getCachedSlimWorkspaces,
  getCachedSoloWorkspace,
} from "@/rsc-data/user/workspaces";

async function SoloWorkspaceTips() {
  try {
    const workspace = await getCachedSoloWorkspace();
    return <SidebarTipsNav workspace={workspace} />;
  } catch (e) {
    console.log(e);
    return null;
  }
}

async function SwitcherWrapper() {
  const slimWorkspaces = await getCachedSlimWorkspaces();
  return <SwitcherAndToggle slimWorkspaces={slimWorkspaces} />;
}

async function UserSidebarContent() {
  await connection();
  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader>
        <Suspense>
          <SwitcherWrapper />
        </Suspense>
      </SidebarHeader>
      <SidebarContent>
        <SidebarAdminPanelNav />
        <SidebarPlatformNav />
        <Suspense>
          <SoloWorkspaceTips />
        </Suspense>
      </SidebarContent>
      <SidebarFooter>
        <SidebarFooterUserNav />
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  );
}

export async function UserSidebar() {
  return (
    <Suspense>
      <UserSidebarContent />
    </Suspense>
  );
}
