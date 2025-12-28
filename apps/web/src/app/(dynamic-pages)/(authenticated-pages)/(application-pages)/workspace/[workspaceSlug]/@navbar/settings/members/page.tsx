import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
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
        segments={WORKSPACE_BREADCRUMBS["settings/members"]}
        workspaceSlug={workspaceSlug}
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
    <Suspense fallback={<Skeleton className="h-[24px] w-[48px]" />}>
      <WorkspaceSettingsMembersNavbarContent params={params} />
    </Suspense>
  );
}
