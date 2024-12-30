import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { ProjectsFilter } from "@/utils/zod-schemas/params";
import type { Metadata } from "next";
import { Suspense } from "react";
import { DashboardClientWrapper } from "./DashboardClientWrapper";
import { ProjectsLoadingFallback } from "./ProjectsLoadingFallback";
import { WorkspaceGraphs } from "./graphs/WorkspaceGraphs";
import { ProjectsTable } from "./projects/ProjectsTable";

export type DashboardProps = {
  workspaceSlug: string;
  projectFilters: ProjectsFilter;
};

export async function WorkspaceDashboard({
  workspaceSlug,
  projectFilters,
}: DashboardProps) {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

  return (
    <DashboardClientWrapper>
      <Suspense fallback={<ProjectsLoadingFallback quantity={3} />}>
        <ProjectsTable workspaceId={workspace.id} />
      </Suspense>
      <WorkspaceGraphs />
    </DashboardClientWrapper>
  );
}

export async function generateMetadata({
  workspaceSlug,
}: DashboardProps): Promise<Metadata> {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

  return {
    title: `Dashboard | ${workspace.name}`,
    description: `View your projects and team members for ${workspace.name}`,
  };
}
