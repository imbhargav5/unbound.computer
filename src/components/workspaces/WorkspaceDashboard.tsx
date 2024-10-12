import { CreateProjectDialog } from "@/components/CreateProjectDialog";
import { ProjectsCardList } from "@/components/Projects/ProjectsCardList";
import { Search } from "@/components/Search";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getProjects } from "@/data/user/projects";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { cn } from "@/utils/cn";
import { getWorkspaceSubPath } from "@/utils/workspaces";
import { ProjectsFilter } from "@/utils/zod-schemas/params";
import { Layers } from "lucide-react";
import type { Metadata } from "next";
import { Suspense } from "react";
import { Typography } from "../ui/Typography";
import { DashboardClientWrapper } from "./DashboardClientWrapper";
import { ProjectsLoadingFallback } from "./ProjectsLoadingFallback";
import { WorkspaceGraphs } from "./graphs/WorkspaceGraphs";

async function Projects({
  workspaceId,
  projectFilters,
}: {
  workspaceId: string;
  projectFilters: ProjectsFilter;
}) {
  const projects = await getProjects({
    workspaceId,
    ...projectFilters,
  });
  return <ProjectsCardList projects={projects} />;
}

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
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-6">
          <CardTitle
            data-testid="dashboard-title"
            className="text-3xl font-bold tracking-tight"
          >
            Dashboard
          </CardTitle>
          <div className="flex space-x-4">
            <CreateProjectDialog workspaceId={workspace.id} />
          </div>
        </CardHeader>
        <CardContent>
          <div
            className={cn(
              "flex mb-6", // Common styles
              "flex-col space-y-2", // Mobile styles
              "md:flex-row md:items-center md:justify-between md:space-y-0", // md styles
            )}
          >
            <Typography.H4 className="my-0">Recent Projects</Typography.H4>
            <div className="flex items-center space-x-4">
              <Search className="w-[200px]" placeholder="Search projects" />
              <Button variant="secondary" size="sm" asChild>
                <Link href={getWorkspaceSubPath(workspace, "projects")}>
                  <Layers className="mr-2 h-4 w-4" />
                  View all projects
                </Link>
              </Button>
            </div>
          </div>
          <Suspense fallback={<ProjectsLoadingFallback quantity={3} />}>
            <Projects
              workspaceId={workspace.id}
              projectFilters={projectFilters}
            />
            {projectFilters.query && (
              <p className="mt-4 text-sm text-muted-foreground">
                Searching for{" "}
                <span className="font-medium">{projectFilters.query}</span>
              </p>
            )}
          </Suspense>
        </CardContent>
      </Card>
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
