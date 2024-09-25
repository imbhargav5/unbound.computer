import { WorkspaceProjects } from "@/components/workspaces/projects/WorkspaceProjects";
import {
  projectsfilterSchema,
  workspaceSlugParamSchema
} from "@/utils/zod-schemas/params";
import type { Metadata } from "next";


export const metadata: Metadata = {
  title: "Projects",
  description: "You can create projects within teams, or within your organization.",
};

export default async function Page({
  params,
  searchParams,
}: {
  params: unknown;
  searchParams: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const projectFilters = projectsfilterSchema.parse(searchParams);
  return <WorkspaceProjects workspaceSlug={workspaceSlug} projectFilters={projectFilters} />
}
