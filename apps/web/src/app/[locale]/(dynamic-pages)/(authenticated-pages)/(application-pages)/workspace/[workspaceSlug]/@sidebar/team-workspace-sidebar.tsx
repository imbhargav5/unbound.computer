// OrganizationSidebar.tsx (Server Component)

import { Suspense } from "react";
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
  getCachedWorkspaceBySlug,
} from "@/rsc-data/user/workspaces";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

async function HeaderContent({ params }: { params: Promise<unknown> }) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(await params);
  const [workspace, slimWorkspaces] = await Promise.all([
    getCachedWorkspaceBySlug(workspaceSlug),
    getCachedSlimWorkspaces(),
  ]);
  return (
    <SwitcherAndToggle
      slimWorkspaces={slimWorkspaces}
      workspaceId={workspace.id}
    />
  );
}

async function Content({ params }: { params: Promise<unknown> }) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(await params);
  const [workspace] = await Promise.all([
    getCachedWorkspaceBySlug(workspaceSlug),
  ]);
  return (
    <>
      <SidebarWorkspaceNav workspace={workspace} />
      <SidebarAdminPanelNav />
      <SidebarTipsNav workspace={workspace} />
    </>
  );
}

export async function TeamWorkspaceSidebar({
  params,
}: {
  params: Promise<unknown>;
}) {
  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader>
        <Suspense
          fallback={
            <>
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
            </>
          }
        >
          <HeaderContent params={params} />
        </Suspense>
      </SidebarHeader>
      <SidebarContent>
        <Suspense
          fallback={
            <>
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
            </>
          }
        >
          <Content params={params} />
        </Suspense>
      </SidebarContent>
      <SidebarFooter>
        <SidebarPlatformNav />
        <SidebarFooterUserNav />
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  );
}
