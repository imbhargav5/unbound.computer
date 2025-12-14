import type { Metadata } from "next";
import { Suspense } from "react";
import { DashboardLoadingFallback } from "@/components/workspaces/dashboard-loading-fallback";
import { WorkspaceDashboard } from "@/components/workspaces/workspace-dashboard";
import { getCachedSoloWorkspace } from "@/rsc-data/user/workspaces";

export async function generateMetadata(): Promise<Metadata> {
  const workspace = await getCachedSoloWorkspace();
  return {
    title: `${workspace.name} | Workspace Dashboard`,
    description: `View your projects and team members for ${workspace.name}`,
  };
}

async function WorkspaceDashboardContent() {
  const workspace = await getCachedSoloWorkspace();
  return <WorkspaceDashboard workspaceSlug={workspace.slug} />;
}

export default async function WorkspaceDashboardPage() {
  return (
    <Suspense fallback={<DashboardLoadingFallback />}>
      <WorkspaceDashboardContent />
    </Suspense>
  );
}
