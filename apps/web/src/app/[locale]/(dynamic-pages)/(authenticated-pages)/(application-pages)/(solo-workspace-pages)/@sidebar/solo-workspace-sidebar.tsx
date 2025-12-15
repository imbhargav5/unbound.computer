// SoloWorkspaceSidebar.tsx (Server Component)

import { Fragment, Suspense } from "react";
import { SidebarAdminPanelNav } from "@/components/sidebar-admin-panel-nav";
import { SwitcherAndToggle } from "@/components/sidebar-components/switcher-and-toggle";
import { SidebarFooterUserNav } from "@/components/sidebar-footer-user-nav";
import { SidebarPlatformNav } from "@/components/sidebar-platform-nav";
import { SidebarTipsNav } from "@/components/sidebar-tips-nav";
import { SidebarWorkspaceNav } from "@/components/sidebar-workspace-nav";
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

async function HeaderContent() {
  const [workspace, slimWorkspaces] = await Promise.all([
    getCachedSoloWorkspace(),
    getCachedSlimWorkspaces(),
  ]);
  return (
    <SwitcherAndToggle
      slimWorkspaces={slimWorkspaces}
      workspaceId={workspace.id}
    />
  );
}

async function Content() {
  const workspace = await getCachedSoloWorkspace();
  return (
    <>
      <SidebarWorkspaceNav workspace={workspace} />
      <SidebarAdminPanelNav />
      <SidebarTipsNav workspace={workspace} />
    </>
  );
}

async function DynamicHeaderContent() {
  return (
    <Suspense
      fallback={
        <>
          <Skeleton className="h-8 w-full" />
          <Skeleton className="h-8 w-full" />
        </>
      }
    >
      <HeaderContent />
    </Suspense>
  );
}

async function DynamicContent() {
  return (
    <Suspense
      fallback={
        <>
          <Skeleton className="h-8 w-full" />
          <Skeleton className="h-8 w-full" />
          <Skeleton className="h-8 w-full" />
        </>
      }
    >
      <Content />
    </Suspense>
  );
}

async function SoloWorkspaceSidebarContent({
  headerContent,
  content,
  footerUserNav,
}: {
  headerContent: React.ReactNode;
  content: React.ReactNode;
  footerUserNav: React.ReactNode;
}) {
  "use cache";
  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader>{headerContent}</SidebarHeader>
      <SidebarContent>
        <Fragment key="content">{content}</Fragment>
        <Fragment key="sidebar-platform-nav">
          <SidebarPlatformNav />
        </Fragment>
      </SidebarContent>
      <SidebarFooter>{footerUserNav}</SidebarFooter>
      <SidebarRail />
    </Sidebar>
  );
}

export async function SoloWorkspaceSidebar() {
  return (
    <SoloWorkspaceSidebarContent
      content={<DynamicContent />}
      footerUserNav={<SidebarFooterUserNav />}
      headerContent={<DynamicHeaderContent />}
    />
  );
}
