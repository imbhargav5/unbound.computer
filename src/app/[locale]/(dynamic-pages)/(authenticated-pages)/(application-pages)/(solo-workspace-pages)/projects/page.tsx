import { WorkspaceProjects } from "@/components/workspaces/projects/WorkspaceProjects";
import { getCachedSoloWorkspace } from "@/rsc-data/user/workspaces";
import { projectsfilterSchema } from "@/utils/zod-schemas/params";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Projects",
  description:
    "You can create projects within teams, or within your organization.",
};

export default async function Page({
  searchParams,
}: {
  searchParams: unknown;
}) {
  const { slug: workspaceSlug } = await getCachedSoloWorkspace();
  const projectFilters = projectsfilterSchema.parse(searchParams);
  return (
    <WorkspaceProjects
      workspaceSlug={workspaceSlug}
      projectFilters={projectFilters}
    />
  );
}
