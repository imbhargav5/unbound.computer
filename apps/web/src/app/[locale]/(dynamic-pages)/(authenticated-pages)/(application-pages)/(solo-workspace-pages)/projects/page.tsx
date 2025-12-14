import type { Metadata } from "next";
import { Suspense } from "react";
import { DashboardClientWrapper } from "@/components/workspaces/dashboard-client-wrapper";
import { ProjectsTable } from "@/components/workspaces/projects/projects-table";
import { ProjectsLoadingFallback } from "@/components/workspaces/projects-loading-fallback";
import {
  getCachedLoggedInUserWorkspaceRole,
  getCachedSoloWorkspace,
} from "@/rsc-data/user/workspaces";

export const metadata: Metadata = {
  title: "Projects",
  description: "View and manage your projects",
};

async function ProjectsContent() {
  const { id: workspaceId } = await getCachedSoloWorkspace();
  const workspaceRole = await getCachedLoggedInUserWorkspaceRole(workspaceId);
  return (
    <DashboardClientWrapper>
      <ProjectsTable workspaceId={workspaceId} workspaceRole={workspaceRole} />
    </DashboardClientWrapper>
  );
}

export default async function Page() {
  return (
    <Suspense fallback={<ProjectsLoadingFallback quantity={3} />}>
      <ProjectsContent />
    </Suspense>
  );
}
