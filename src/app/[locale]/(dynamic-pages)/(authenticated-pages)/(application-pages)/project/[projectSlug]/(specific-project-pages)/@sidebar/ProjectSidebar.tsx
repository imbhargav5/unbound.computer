import { DesktopSidebarFallback } from "@/components/SidebarComponents/SidebarFallback";
import { getSlimProjectBySlug } from "@/data/user/projects";
import { getWorkspaceById } from "@/data/user/workspaces";
import { getCachedProjectBySlug } from "@/rsc-data/user/projects";
import { getCachedSlimWorkspaces } from "@/rsc-data/user/workspaces";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";
import { Suspense } from "react";
import { ProjectSidebarClient } from "./ProjectSidebarClient";

export async function ProjectSidebar({ params }: { params: unknown }) {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);
  const [slimWorkspaces, fullProject] = await Promise.all([
    getCachedSlimWorkspaces(),
    getCachedProjectBySlug(project.slug),
  ]);
  const workspaceId = fullProject.workspace_id;
  const workspace = await getWorkspaceById(workspaceId);

  return (
    <Suspense fallback={<DesktopSidebarFallback />}>
      <ProjectSidebarClient
        workspace={workspace}
        project={fullProject}
        slimWorkspaces={slimWorkspaces}
      />
    </Suspense>
  );
}
