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
  getCachedProjectBySlug,
  getCachedSlimProjectBySlug,
} from "@/rsc-data/user/projects";
import {
  getCachedSlimWorkspaces,
  getCachedWorkspaceById,
} from "@/rsc-data/user/workspaces";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";
import { ProjectSidebarGroup } from "./project-sidebar-group";

async function HeaderContent({ params }: { params: Promise<unknown> }) {
  const { projectSlug } = projectSlugParamSchema.parse(await params);
  const slimProject = await getCachedSlimProjectBySlug(projectSlug);
  const fullProject = await getCachedProjectBySlug(slimProject.slug);
  const [slimWorkspaces, workspace] = await Promise.all([
    getCachedSlimWorkspaces(),
    getCachedWorkspaceById(fullProject.workspace_id),
  ]);
  return (
    <SwitcherAndToggle
      slimWorkspaces={slimWorkspaces}
      workspaceId={workspace.id}
    />
  );
}

async function Content({ params }: { params: Promise<unknown> }) {
  const { projectSlug } = projectSlugParamSchema.parse(await params);
  const slimProject = await getCachedSlimProjectBySlug(projectSlug);
  const fullProject = await getCachedProjectBySlug(slimProject.slug);
  const workspace = await getCachedWorkspaceById(fullProject.workspace_id);
  return (
    <>
      <ProjectSidebarGroup project={fullProject} workspace={workspace} />
      <SidebarWorkspaceNav withLinkLabelPrefix workspace={workspace} />
      <SidebarAdminPanelNav />
      <SidebarTipsNav workspace={workspace} />
    </>
  );
}

export async function ProjectSidebar({ params }: { params: Promise<unknown> }) {
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
