import { CreateProjectDialog } from "@/components/CreateProjectDialog";
import { PageHeading } from "@/components/PageHeading";
import { Pagination } from "@/components/Pagination";
import { Search } from "@/components/Search";
import { T } from "@/components/ui/Typography";
import { getProjects, getProjectsTotalCount } from "@/data/user/projects";
import { getWorkspaceBySlug } from "@/data/user/workspaces";
import {
  projectsfilterSchema,
  workspaceSlugParamSchema
} from "@/utils/zod-schemas/params";
import type { Metadata } from "next";
import { Suspense } from "react";
import type { DashboardProps } from "../page";
import { WorkspaceProjectsTable } from "./WorkspaceProjectsTable";

async function ProjectsTableWithPagination({
  workspaceId,
  searchParams,
}: { workspaceId: string; searchParams: unknown }) {
  const filters = projectsfilterSchema.parse(searchParams);
  const [projects, totalPages] = await Promise.all([
    getProjects({ ...filters, workspaceId }),
    getProjectsTotalCount({ ...filters, workspaceId }),
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
  description: "You can create projects within teams, or within your organization.",
};

export default async function Page({
  params,
  searchParams,
}: DashboardProps) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  const filters = projectsfilterSchema.parse(searchParams);

  return (
    <div className="flex flex-col gap-4 w-full mt-8">
      <PageHeading
        title="Projects"
        subTitle="You can create projects within teams, or within your organization."
      />
      <div className="flex justify-between gap-2">
        <div className="md:w-1/3">
          <Search placeholder="Search projects" />
          {filters.query && (
            <p className="text-sm ml-2 mt-4">
              Searching for <span className="font-bold">{filters.query}</span>
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
            searchParams={searchParams}
          />
        </Suspense>
      }
    </div>
  );
}
