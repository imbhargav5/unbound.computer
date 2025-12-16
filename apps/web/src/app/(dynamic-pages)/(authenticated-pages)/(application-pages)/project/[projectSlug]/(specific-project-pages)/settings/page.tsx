import { Suspense } from "react";
import { T } from "@/components/ui/typography-ui";
import { getSlimProjectBySlug } from "@/data/user/projects";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";

async function ProjectSettingsContent(props: { params: Promise<unknown> }) {
  const params = await props.params;
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);
  return (
    <div className="space-y-2">
      <T.H3>Project Settings</T.H3>
      <T.Subtle>
        Add settings for your projects depending on your usecase
      </T.Subtle>
    </div>
  );
}

export default async function ProjectSettings(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <ProjectSettingsContent params={props.params} />
    </Suspense>
  );
}
