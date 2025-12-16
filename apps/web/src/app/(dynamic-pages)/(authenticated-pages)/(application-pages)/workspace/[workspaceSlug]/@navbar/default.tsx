// https://github.com/vercel/next.js/issues/58272

import { Skeleton } from "@/components/ui/skeleton";
import { WORKSPACE_BREADCRUMBS } from "@/components/workspaces/breadcrumb-config";
import { WorkspaceBreadcrumb } from "@/components/workspaces/workspace-breadcrumb";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import { Suspense } from "react";

async function WorkspaceDefaultNavbarContent({
  params,
}: {
  params: Promise<unknown>;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(await params);
  return (
    <>
      <WorkspaceBreadcrumb segments={WORKSPACE_BREADCRUMBS.home} workspaceSlug={workspaceSlug} />
    </>
  );
}

export default async function WorkspaceDefaultNavbar({
  params,
}: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense fallback={<Skeleton className="h-[24px] w-[48px]" />}>
      <WorkspaceDefaultNavbarContent params={params} />
    </Suspense>
  );
}
