import { CreateProjectDialog } from "@/components/CreateProjectDialog";
import { PageHeading } from "@/components/PageHeading";
import { Pagination } from "@/components/Pagination";
import { Search } from "@/components/Search";
import { T } from "@/components/ui/Typography";
import { getProjects, getProjectsTotalCount } from "@/data/user/projects";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { ProjectsFilter } from "@/utils/zod-schemas/params";
import type { Metadata } from "next";
import { Suspense } from "react";
import type { DashboardProps } from "../WorkspaceDashboard";
import { WorkspaceProjectsTable } from "./WorkspaceProjectsTable";

async function ProjectsTableWithPagination({
  workspaceId,
  projectFilters,
}: {
  workspaceId: string;
  projectFilters: ProjectsFilter;
}) {
  const [projects, totalPages] = await Promise.all([
    getProjects({ ...projectFilters, workspaceId }),
    getProjectsTotalCount({ ...projectFilters, workspaceId }),
  ]);

  return (
    <>
      <WorkspaceProjectsTable projects={projects} />
      <Pagination totalPages={totalPages} />
    </>
  );
}

export const metadata: Metadata = {
  title: "Projects",
  description:
    "You can create projects within teams, or within your organization.",
};

export async function WorkspaceProjects({
  workspaceSlug,
  projectFilters,
}: DashboardProps) {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

  return (
    <div className="flex flex-col gap-4 w-full mt-8">
      <PageHeading
        title="Projects"
        subTitle="You can create projects within teams, or within your organization."
      />
      <div className="flex justify-between gap-2">
        <div className="md:w-1/3">
          <Search placeholder="Search projects" />
          {projectFilters.query && (
            <p className="text-sm ml-2 mt-4">
              Searching for{" "}
              <span className="font-bold">{projectFilters.query}</span>
            </p>
          )}
        </div>

        <CreateProjectDialog workspaceId={workspace.id} />
      </div>
      {
        <Suspense
          fallback={
            <T.P className="text-muted-foreground my-6">
              Loading projects...
            </T.P>
          }
        >
          <ProjectsTableWithPagination
            workspaceId={workspace.id}
            projectFilters={projectFilters}
          />
        </Suspense>
      }
    </div>
  );
}
