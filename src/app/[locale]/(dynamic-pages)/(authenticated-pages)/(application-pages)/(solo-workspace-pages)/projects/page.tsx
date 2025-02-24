import { DashboardClientWrapper } from "@/components/workspaces/DashboardClientWrapper";
import { ProjectsLoadingFallback } from "@/components/workspaces/ProjectsLoadingFallback";
import { ProjectsTable } from "@/components/workspaces/projects/ProjectsTable";
import {
  getCachedLoggedInUserWorkspaceRole,
  getCachedSoloWorkspace,
} from "@/rsc-data/user/workspaces";
import type { Metadata } from "next";
import { Suspense } from "react";

export const metadata: Metadata = {
  title: "Projects",
  description: "View and manage your projects",
};

export default async function Page() {
  const { id: workspaceId } = await getCachedSoloWorkspace();
  const workspaceRole = await getCachedLoggedInUserWorkspaceRole(workspaceId);
  return (
    <DashboardClientWrapper>
      <Suspense fallback={<ProjectsLoadingFallback quantity={3} />}>
        <ProjectsTable
          workspaceId={workspaceId}
          workspaceRole={workspaceRole}
        />
      </Suspense>
    </DashboardClientWrapper>
  );
}
