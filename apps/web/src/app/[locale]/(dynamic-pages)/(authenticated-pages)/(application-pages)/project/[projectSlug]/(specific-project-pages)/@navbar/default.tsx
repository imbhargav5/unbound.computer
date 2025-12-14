// https://github.com/vercel/next.js/issues/58272

import { ProjectBreadcrumb } from "@/components/projects/project-breadcrumb";
import { PROJECT_BREADCRUMBS } from "@/components/projects/project-breadcrumb-config";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";

export default async function ProjectNavbar(props: {
  params: Promise<unknown>;
}) {
  const params = await props.params;
  const { projectSlug } = projectSlugParamSchema.parse(params);
  return (
    <ProjectBreadcrumb
      basePath={`/project/${projectSlug}`}
      segments={PROJECT_BREADCRUMBS.home}
    />
  );
}
