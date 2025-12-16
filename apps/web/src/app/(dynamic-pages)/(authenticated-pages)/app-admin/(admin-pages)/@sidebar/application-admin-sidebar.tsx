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
  getCachedDefaultWorkspace,
  getCachedSlimWorkspaces,
} from "@/rsc-data/user/workspaces";

async function DefaultWorkspaceTips() {
  const defaultWorkspace = await getCachedDefaultWorkspace();
  if (!defaultWorkspace) return null;
  return <SidebarTipsNav workspace={defaultWorkspace.workspace} />;
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

async function DynamicDefaultWorkspaceTips() {
  return (
    <Suspense fallback={<Skeleton className="h-10 w-full" />}>
      <DefaultWorkspaceTips />
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
  workspaceTips,
  footerUserNav,
}: {
  switcherWrapper: React.ReactNode;
  sidebarAdminPanelNav: React.ReactNode;
  workspaceTips: React.ReactNode;
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
        <Fragment key="workspace-tips">{workspaceTips}</Fragment>
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
      switcherWrapper={<DynamicSwitcherAndToggleWrapper />}
      workspaceTips={<DynamicDefaultWorkspaceTips />}
    />
  );
}
