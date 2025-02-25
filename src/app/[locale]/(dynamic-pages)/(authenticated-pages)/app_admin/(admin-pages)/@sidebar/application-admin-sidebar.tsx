// OrganizationSidebar.tsx (Server Component)

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
import { notFound, unstable_rethrow } from "next/navigation";
import { Suspense } from "react";
async function SoloWorkspaceTips() {
  try {
    const workspace = await getCachedSoloWorkspace();
    return <SidebarTipsNav workspace={workspace} />;
  } catch (e) {
    console.error(e);
    return null;
  }
}
export async function ApplicationAdminSidebar() {
  try {
    const slimWorkspaces = await getCachedSlimWorkspaces();
    return (
      <Sidebar variant="inset" collapsible="icon">
        <SidebarHeader>
          <SwitcherAndToggle slimWorkspaces={slimWorkspaces} />
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
  } catch (e) {
    unstable_rethrow(e);
    console.error(e);
    return notFound();
  }
}
