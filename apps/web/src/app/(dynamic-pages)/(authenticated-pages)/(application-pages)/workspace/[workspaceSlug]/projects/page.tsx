import type { Metadata } from "next";
import { Suspense } from "react";
import { DashboardClientWrapper } from "@/components/workspaces/dashboard-client-wrapper";
import { ProjectsTable } from "@/components/workspaces/projects/projects-table";
import { ProjectsLoadingFallback } from "@/components/workspaces/projects-loading-fallback";
import {
  getCachedLoggedInUserWorkspaceRole,
  getCachedWorkspaceBySlug,
} from "@/rsc-data/user/workspaces";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

export const metadata: Metadata = {
  title: "Projects",
  description: "View and manage your workspace projects",
};

async function ProjectsContent(props: { params: Promise<unknown> }) {
  const params = await props.params;
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);

  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  const workspaceRole = await getCachedLoggedInUserWorkspaceRole(workspace.id);

  return (
    <DashboardClientWrapper>
      <Suspense fallback={<ProjectsLoadingFallback quantity={3} />}>
        <ProjectsTable
          workspaceId={workspace.id}
          workspaceRole={workspaceRole}
        />
      </Suspense>
    </DashboardClientWrapper>
  );
}

export default async function Page(props: { params: Promise<unknown> }) {
  return (
    <Suspense>
      <ProjectsContent params={props.params} />
    </Suspense>
  );
}
