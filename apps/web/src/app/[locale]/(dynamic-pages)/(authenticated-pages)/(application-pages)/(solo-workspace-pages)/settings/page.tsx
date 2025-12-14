import type { Metadata } from "next";
import { Suspense } from "react";
import { WorkspaceSettings } from "@/components/workspaces/settings/workspace-settings";
import { getCachedSoloWorkspace } from "@/rsc-data/user/workspaces";

export const metadata: Metadata = {
  title: "Settings",
  description: "You can edit your organization's settings here.",
};

async function SettingsContent() {
  const workspace = await getCachedSoloWorkspace();
  return <WorkspaceSettings workspaceSlug={workspace.slug} />;
}

export default async function EditOrganizationPage() {
  return (
    <Suspense>
      <SettingsContent />
    </Suspense>
  );
}
