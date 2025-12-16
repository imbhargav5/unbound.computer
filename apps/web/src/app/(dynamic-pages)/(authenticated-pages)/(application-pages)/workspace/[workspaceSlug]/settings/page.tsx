import type { Metadata } from "next";
import { Suspense } from "react";
import { WorkspaceSettings } from "@/components/workspaces/settings/workspace-settings";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

export const metadata: Metadata = {
  title: "Settings",
  description: "You can edit your organization's settings here.",
};

async function SettingsContent(props: { params: Promise<unknown> }) {
  const params = await props.params;
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);

  return <WorkspaceSettings workspaceSlug={workspaceSlug} />;
}

export default async function EditOrganizationPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <SettingsContent params={props.params} />
    </Suspense>
  );
}
