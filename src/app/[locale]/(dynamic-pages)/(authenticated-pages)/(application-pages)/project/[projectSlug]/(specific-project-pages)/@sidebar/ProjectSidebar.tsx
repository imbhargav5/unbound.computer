import { DesktopSidebarFallback } from "@/components/SidebarComponents/SidebarFallback";
import { getProjectBySlug, getSlimProjectBySlug } from "@/data/user/projects";
import { fetchSlimWorkspaces, getWorkspaceById } from "@/data/user/workspaces";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";
import { Suspense } from "react";
import { ProjectSidebarClient } from "./ProjectSidebarClient";

export async function ProjectSidebar({ params }: { params: unknown }) {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);
  const [slimWorkspaces, fullProject] = await Promise.all([
    fetchSlimWorkspaces(),
    getProjectBySlug(project.slug),
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
