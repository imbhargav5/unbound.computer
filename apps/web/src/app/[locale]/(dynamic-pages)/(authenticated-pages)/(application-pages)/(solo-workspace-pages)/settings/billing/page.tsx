import { Suspense } from "react";
import { WorkspaceBilling } from "@/components/workspaces/settings/billing/workspace-billing";
import { getCachedSoloWorkspace } from "@/rsc-data/user/workspaces";

async function BillingContent() {
  const workspace = await getCachedSoloWorkspace();
  return <WorkspaceBilling workspaceSlug={workspace.slug} />;
}

export default async function WorkspaceSettingsBillingPage() {
  return (
    <Suspense>
      <BillingContent />
    </Suspense>
  );
}
