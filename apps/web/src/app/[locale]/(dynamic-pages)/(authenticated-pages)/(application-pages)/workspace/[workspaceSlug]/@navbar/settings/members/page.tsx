import { Suspense } from "react";
import { WORKSPACE_BREADCRUMBS } from "@/components/workspaces/breadcrumb-config";
import { WorkspaceBreadcrumb } from "@/components/workspaces/workspace-breadcrumb";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

async function WorkspaceSettingsMembersNavbarContent({
  params,
}: {
  params: Promise<unknown>;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(await params);
  return (
    <>
      <WorkspaceBreadcrumb
        basePath={`/workspace/${workspaceSlug}`}
        segments={WORKSPACE_BREADCRUMBS["settings/members"]}
      />
    </>
  );
}

export default async function WorkspaceSettingsMembersNavbar({
  params,
}: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <WorkspaceSettingsMembersNavbarContent params={params} />
    </Suspense>
  );
}
