import { ProjectBreadcrumb } from "@/components/projects/project-breadcrumb";
import { PROJECT_BREADCRUMBS } from "@/components/projects/project-breadcrumb-config";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";

export default async function SettingsNavbar({
  params,
}: {
  params: Promise<unknown>;
}) {
  const { projectSlug } = projectSlugParamSchema.parse(await params);
  return (
    <ProjectBreadcrumb
      projectSlug={projectSlug}
      segments={PROJECT_BREADCRUMBS.settings}
    />
  );
}
