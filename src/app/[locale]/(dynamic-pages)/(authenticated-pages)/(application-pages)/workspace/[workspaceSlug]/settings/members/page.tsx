
import { WorkspaceMembers } from "@/components/workspaces/settings/members/WorkspaceMembers";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Members",
  description: "You can edit your workspace's members here.",
};



export default async function WorkspaceTeamPage({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  return <WorkspaceMembers workspaceSlug={workspaceSlug} />
}
