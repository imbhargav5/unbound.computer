import { Suspense } from "react";
import { WorkspaceBilling } from "@/components/workspaces/settings/billing/workspace-billing";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

async function BillingContent(props: { params: Promise<unknown> }) {
  const params = await props.params;
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  return <WorkspaceBilling workspaceSlug={workspaceSlug} />;
}

export default async function WorkspaceSettingsBillingPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <BillingContent params={props.params} />
    </Suspense>
  );
}
