import { Suspense } from "react";
import { WORKSPACE_BREADCRUMBS } from "@/components/workspaces/breadcrumb-config";
import { WorkspaceBreadcrumb } from "@/components/workspaces/workspace-breadcrumb";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import { Skeleton } from "@/components/ui/skeleton";

async function WorkspaceProjectsNavbarContent({
  params,
}: {
  params: Promise<unknown>;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(await params);
  return (
    <WorkspaceBreadcrumb
      segments={WORKSPACE_BREADCRUMBS.projects}
      workspaceSlug={workspaceSlug}
    />
  );
}

export default async function WorkspaceProjectsNavbar({
  params,
}: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense fallback={<Skeleton className="h-[24px] w-[48px]" />}>
      <WorkspaceProjectsNavbarContent params={params} />
    </Suspense>
  );
}
