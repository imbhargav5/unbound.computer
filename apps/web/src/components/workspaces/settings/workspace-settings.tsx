import type { Metadata } from "next";
import { Suspense } from "react";
import { Typography } from "@/components/ui/typography-ui";
import {
  getCachedLoggedInUserWorkspaceRole,
  getCachedWorkspaceBySlug,
} from "@/rsc-data/user/workspaces";
import { DeleteWorkspace } from "./delete-workspace";
import { EditWorkspaceForm } from "./edit-workspace-form";
import { SetDefaultWorkspacePreference } from "./set-default-workspace-preference";
import { SettingsFormSkeleton } from "./settings-skeletons";

async function EditWorkspace({ workspaceSlug }: { workspaceSlug: string }) {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return <EditWorkspaceForm workspace={workspace} />;
}

async function AdminDeleteWorkspace({
  workspaceId,
  workspaceName,
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
    <DeleteWorkspace workspaceId={workspaceId} workspaceName={workspaceName} />
  );
}

export const metadata: Metadata = {
  title: "Settings",
  description: "You can edit your organization's settings here.",
};

export async function WorkspaceSettings({
  workspaceSlug,
}: {
  workspaceSlug: string;
}) {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  const workspaceRole = await getCachedLoggedInUserWorkspaceRole(workspace.id);
  const isWorkspaceAdmin =
    workspaceRole === "admin" || workspaceRole === "owner";

  // For now, in this starter kit, we're allowing all users to edit the workspace settings except for the read-only members
  const canEditWorkspace =
    workspaceRole === "admin" ||
    workspaceRole === "owner" ||
    workspaceRole === "member";

  return (
    <div className="space-y-4">
      <div>
        <Typography.H2>Workspace Settings</Typography.H2>
        <Typography.Subtle>
          {isWorkspaceAdmin
            ? "Manage your workspace settings and preferences."
            : "View and manage your workspace preferences."}
        </Typography.Subtle>
      </div>

      {canEditWorkspace && (
        <>
          <Suspense fallback={<SettingsFormSkeleton />}>
            <EditWorkspace workspaceSlug={workspaceSlug} />
          </Suspense>
        </>
      )}

      {isWorkspaceAdmin && (
        <Suspense>
          <AdminDeleteWorkspace
            workspaceId={workspace.id}
            workspaceName={workspace.name}
          />
        </Suspense>
      )}

      <Suspense fallback={<SettingsFormSkeleton />}>
        <SetDefaultWorkspacePreference workspaceSlug={workspaceSlug} />
      </Suspense>
    </div>
  );
}
