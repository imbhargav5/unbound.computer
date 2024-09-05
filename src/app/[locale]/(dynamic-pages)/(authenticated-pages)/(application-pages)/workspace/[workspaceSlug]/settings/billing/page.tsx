import { T } from "@/components/ui/Typography";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import { Suspense } from "react";

import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { WorkspaceWithMembershipType } from "@/types";
import type { Metadata } from "next";

async function Subscription({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  return null;
}

export const metadata: Metadata = {
  title: "Billing",
  description: "You can edit your organization's billing details here.",
};

export default async function OrganizationSettingsPage({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return (
    <Suspense fallback={<T.Subtle>Loading billing details...</T.Subtle>}>
      <Subscription workspace={workspace} />
    </Suspense>
  );
}
