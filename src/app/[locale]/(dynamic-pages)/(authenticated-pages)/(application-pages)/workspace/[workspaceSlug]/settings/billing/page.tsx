import { WorkspaceBilling } from "@/components/workspaces/settings/billing/WorkspaceBilling";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";


export default async function WorkspaceSettingsBillingPage({ params }: { params: unknown }) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  return <WorkspaceBilling workspaceSlug={workspaceSlug} />
};

