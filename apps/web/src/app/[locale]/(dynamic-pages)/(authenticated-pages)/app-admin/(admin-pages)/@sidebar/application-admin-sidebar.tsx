// ApplicationAdminSidebar.tsx (Server Component)

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

async function SwitcherAndToggleWrapper() {
  const slimWorkspaces = await getCachedSlimWorkspaces();
  return <SwitcherAndToggle slimWorkspaces={slimWorkspaces} />;
}

async function DynamicSwitcherAndToggleWrapper() {
  return (
    <Suspense
      fallback={
        <>
          <Skeleton className="h-6 w-16" />
          <Skeleton className="h-6 w-16" />
        </>
      }
    >
      <SwitcherAndToggleWrapper />
    </Suspense>
  );
}

async function DynamicSoloWorkspaceTips() {
  return (
    <Suspense fallback={<Skeleton className="h-10 w-full" />}>
      <SoloWorkspaceTips />
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

async function ApplicationAdminSidebarContent({
  switcherWrapper,
  sidebarAdminPanelNav,
  soloWorkspaceTips,
  footerUserNav,
}: {
  switcherWrapper: React.ReactNode;
  sidebarAdminPanelNav: React.ReactNode;
  soloWorkspaceTips: React.ReactNode;
  footerUserNav: React.ReactNode;
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

export async function ApplicationAdminSidebar() {
  return (
    <ApplicationAdminSidebarContent
      footerUserNav={<SidebarFooterUserNav />}
      sidebarAdminPanelNav={<DynamicSidebarAdminPanelNav />}
      soloWorkspaceTips={<DynamicSoloWorkspaceTips />}
      switcherWrapper={<DynamicSwitcherAndToggleWrapper />}
    />
  );
}
