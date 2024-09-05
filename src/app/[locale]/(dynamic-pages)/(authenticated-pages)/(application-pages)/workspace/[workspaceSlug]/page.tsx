import { CreateProjectDialog } from "@/components/CreateProjectDialog";
import { ProjectsCardList } from "@/components/Projects/ProjectsCardList";
import { Search } from "@/components/Search";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getProjects } from "@/data/user/projects";
import { getWorkspaceBySlug } from "@/data/user/workspaces";
import { getWorkspaceSubPath } from "@/utils/workspaces";
import {
  projectsfilterSchema,
  workspaceSlugParamSchema
} from "@/utils/zod-schemas/params";
import { FileText, Layers } from "lucide-react";
import type { Metadata } from 'next';
import Link from 'next/link';
import { Suspense } from "react";
import type { z } from "zod";
import { DashboardClientWrapper } from "./DashboardClientWrapper";
import { DashboardLoadingFallback } from "./DashboardLoadingFallback";
import ProjectsLoadingFallback from "./ProjectsLoadingFallback";
import { WorkspaceGraphs } from "./_graphs/WorkspaceGraphs";

async function Projects({
  workspaceId,
  filters,
}: {
  workspaceId: string;
  filters: z.infer<typeof projectsfilterSchema>;
}) {
  const projects = await getProjects({
    workspaceId,
    ...filters,
  });
  return <ProjectsCardList projects={projects} />;
}

export type DashboardProps = {
  params: { organizationSlug: string };
  searchParams: unknown;
};

async function Dashboard({ params, searchParams }: DashboardProps) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  const validatedSearchParams = projectsfilterSchema.parse(searchParams);

  return (
    <DashboardClientWrapper>
      <Card >
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-6">
          <CardTitle className="text-3xl font-bold tracking-tight">Dashboard</CardTitle>
          <div className="flex space-x-4">
            <Button variant="outline" size="sm">
              <FileText className="mr-2 h-4 w-4" />
              Export PDF
            </Button>
            <CreateProjectDialog organizationId={workspace.id} />
          </div>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-2xl font-semibold tracking-tight">Recent Projects</h2>
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
              filters={validatedSearchParams}
            />
            {validatedSearchParams.query && (
              <p className="mt-4 text-sm text-muted-foreground">
                Searching for{" "}
                <span className="font-medium">{validatedSearchParams.query}</span>
              </p>
            )}
          </Suspense>
        </CardContent>
      </Card>
      <WorkspaceGraphs />
    </DashboardClientWrapper>
  );
}

export async function generateMetadata({ params }: DashboardProps): Promise<Metadata> {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getWorkspaceBySlug(workspaceSlug);

  return {
    title: `Dashboard | ${workspace.name}`,
    description: `View your projects and team members for ${workspace.name}`,
  };
}

export default async function OrganizationPage({ params, searchParams }: DashboardProps) {
  return (
    <Suspense fallback={<DashboardLoadingFallback />}>
      <Dashboard params={params} searchParams={searchParams} />
    </Suspense>
  );
}
