// OrganizationSidebar.tsx (Server Component)

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
  getCachedSlimWorkspaces,
  getCachedSoloWorkspace,
} from "@/rsc-data/user/workspaces";

async function SoloWorkspaceTips() {
  const workspace = await getCachedSoloWorkspace();
  return <SidebarTipsNav workspace={workspace} />;
}

async function SwitcherWrapper() {
  const slimWorkspaces = await getCachedSlimWorkspaces();
  return <SwitcherAndToggle slimWorkspaces={slimWorkspaces} />;
}

async function DynamicSoloWorkspaceTips() {
  return (
    <Suspense fallback={<Skeleton className="h-10 w-full" />}>
      <SoloWorkspaceTips />
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
  soloWorkspaceTips,
  footerUserNav,
  sidebarAdminPanelNav,
}: {
  switcherWrapper: React.ReactNode;
  soloWorkspaceTips: React.ReactNode;
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
        <Fragment key="solo-workspace-tips">{soloWorkspaceTips}</Fragment>
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
      soloWorkspaceTips={<DynamicSoloWorkspaceTips />}
      switcherWrapper={<DynamicSwitcherWrapper />}
    />
  );
}
