import { WorkspaceProjects } from "@/components/workspaces/projects/WorkspaceProjects";
import {
  projectsfilterSchema,
  workspaceSlugParamSchema,
} from "@/utils/zod-schemas/params";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Projects",
  description:
    "You can create projects within teams, or within your organization.",
};

export default async function Page(props: {
  params: Promise<unknown>;
  searchParams: Promise<unknown>;
}) {
  const searchParams = await props.searchParams;
  const params = await props.params;
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const projectFilters = projectsfilterSchema.parse(searchParams);
  return (
    <WorkspaceProjects
      workspaceSlug={workspaceSlug}
      projectFilters={projectFilters}
    />
  );
}
