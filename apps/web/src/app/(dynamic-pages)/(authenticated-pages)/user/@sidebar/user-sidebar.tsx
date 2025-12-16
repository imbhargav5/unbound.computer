// UserSidebar.tsx (Server Component)

import { Fragment, Suspense } from "react";
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
import { Skeleton } from "@/components/ui/skeleton";
import {
  getCachedDefaultWorkspace,
  getCachedSlimWorkspaces,
} from "@/rsc-data/user/workspaces";

async function DefaultWorkspaceTips() {
  const defaultWorkspace = await getCachedDefaultWorkspace();
  if (!defaultWorkspace) return null;
  return <SidebarTipsNav workspace={defaultWorkspace.workspace} />;
}

async function SwitcherWrapper() {
  const slimWorkspaces = await getCachedSlimWorkspaces();
  return <SwitcherAndToggle slimWorkspaces={slimWorkspaces} />;
}

async function DynamicDefaultWorkspaceTips() {
  return (
    <Suspense fallback={<Skeleton className="h-10 w-full" />}>
      <DefaultWorkspaceTips />
    </Suspense>
  );
}

async function DynamicSwitcherWrapper() {
  return (
    <Suspense fallback={<Skeleton className="h-10 w-full" />}>
      <SwitcherWrapper />
    </Suspense>
  );
}

async function DynamicSidebarAdminPanelNav() {
  return (
    <Suspense fallback={<Skeleton className="h-10 w-full" />}>
      <SidebarAdminPanelNav />
    </Suspense>
  );
}

async function UserSidebarContent({
  switcherWrapper,
  workspaceTips,
  footerUserNav,
  sidebarAdminPanelNav,
}: {
  switcherWrapper: React.ReactNode;
  workspaceTips: React.ReactNode;
  footerUserNav: React.ReactNode;
  sidebarAdminPanelNav: React.ReactNode;
}) {
  "use cache";
  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader>{switcherWrapper}</SidebarHeader>
      <SidebarContent>
        <Fragment key="sidebar-admin-panel-nav">
          {sidebarAdminPanelNav}
        </Fragment>
        <Fragment key="sidebar-platform-nav">
          <SidebarPlatformNav />
        </Fragment>
        <Fragment key="workspace-tips">{workspaceTips}</Fragment>
      </SidebarContent>
      <SidebarFooter>{footerUserNav}</SidebarFooter>
      <SidebarRail />
    </Sidebar>
  );
}

export async function UserSidebar() {
  return (
    <UserSidebarContent
      footerUserNav={<SidebarFooterUserNav />}
      sidebarAdminPanelNav={<DynamicSidebarAdminPanelNav />}
      switcherWrapper={<DynamicSwitcherWrapper />}
      workspaceTips={<DynamicDefaultWorkspaceTips />}
    />
  );
}
