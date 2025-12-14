// https://github.com/vercel/next.js/issues/58272

import { Suspense } from "react";
import { WORKSPACE_BREADCRUMBS } from "@/components/workspaces/breadcrumb-config";
import { WorkspaceBreadcrumb } from "@/components/workspaces/workspace-breadcrumb";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

async function WorkspaceDefaultNavbarContent({
  params,
}: {
  params: Promise<unknown>;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(await params);
  return (
    <>
      <WorkspaceBreadcrumb
        basePath={`/workspace/${workspaceSlug}`}
        segments={WORKSPACE_BREADCRUMBS.home}
      />
    </>
  );
}

export default async function WorkspaceDefaultNavbar({
  params,
}: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <WorkspaceDefaultNavbarContent params={params} />
    </Suspense>
  );
}
