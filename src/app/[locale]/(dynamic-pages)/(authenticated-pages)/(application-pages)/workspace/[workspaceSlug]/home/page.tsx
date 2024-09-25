import { DashboardLoadingFallback } from "@/components/workspaces/DashboardLoadingFallback";
import { WorkspaceDashboard } from "@/components/workspaces/WorkspaceDashboard";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import {
  projectsfilterSchema,
  workspaceSlugParamSchema
} from "@/utils/zod-schemas/params";
import type { Metadata } from 'next';
import { Suspense } from "react";


export async function generateMetadata({ params }: {
  params: unknown;
}): Promise<Metadata> {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

  return {
    title: `Dashboard | ${workspace.name}`,
    description: `View your projects and team members for ${workspace.name}`,
  };
}

export default async function WorkspaceDashboardPage({ params, searchParams }: {
  params: unknown;
  searchParams: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const projectFilters = projectsfilterSchema.parse(searchParams);

  return (
    <Suspense fallback={<DashboardLoadingFallback />}>
      <WorkspaceDashboard workspaceSlug={workspaceSlug} projectFilters={projectFilters} />
    </Suspense>
  );
}
