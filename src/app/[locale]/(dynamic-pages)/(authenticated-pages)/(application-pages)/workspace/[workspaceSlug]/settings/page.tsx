import { getCachedLoggedInUserWorkspaceRole, getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import type { Metadata } from "next";
import { Suspense } from "react";
import { DeleteWorkspace } from "./DeleteWorkspace";
import { EditWorkspaceForm } from "./EditWorkspaceForm";
import { SetDefaultWorkspacePreference } from "./SetDefaultWorkspacePreference";
import { SettingsFormSkeleton } from "./SettingsSkeletons";

async function EditOrganization({
  workspaceSlug,
}: {
  workspaceSlug: string;
}) {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return (
    <EditWorkspaceForm
      workspace={workspace}
      workspaceMembershipType={workspace.membershipType}
    />
  );
}

async function DeleteOrganizationIfAdmin({
  workspaceId,
  workspaceName
}: {
  workspaceId: string;
  workspaceName: string;
}) {
  const workspaceRole = await getCachedLoggedInUserWorkspaceRole(workspaceId);
  const isWorkspaceAdmin =
    workspaceRole === "admin" || workspaceRole === "owner";
  if (!isWorkspaceAdmin) {
    return null;
  }
  return (
    <DeleteWorkspace
      workspaceId={workspaceId}
      workspaceName={workspaceName}
    />
  );
}

export const metadata: Metadata = {
  title: "Settings",
  description: "You can edit your organization's settings here.",
};

export default async function EditOrganizationPage({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

  return (
    <div className="space-y-4">
      <Suspense fallback={<SettingsFormSkeleton />}>
        <EditOrganization workspaceSlug={workspaceSlug} />
      </Suspense>
      <Suspense fallback={<SettingsFormSkeleton />}>
        <SetDefaultWorkspacePreference workspaceSlug={workspaceSlug} />
      </Suspense>
      <Suspense fallback={<SettingsFormSkeleton />}>
        <DeleteOrganizationIfAdmin workspaceId={workspace.id} workspaceName={workspace.name} />
      </Suspense>
    </div>
  );
}
