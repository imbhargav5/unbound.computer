import type { Metadata } from "next";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { DashboardClientWrapper } from "./dashboard-client-wrapper";
import { WorkspaceGraphs } from "./graphs/workspace-graphs";

export type DashboardProps = {
  workspaceSlug: string;
};

export async function WorkspaceDashboard({ workspaceSlug }: DashboardProps) {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return (
    <DashboardClientWrapper>
      {/* Hidden elements for E2E testing */}
      <div className="hidden" data-testid="workspaceId">
        {workspace.id}
      </div>
      <div className="hidden" data-testid="workspaceSlug">
        {workspaceSlug}
      </div>

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
