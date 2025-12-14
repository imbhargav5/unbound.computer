import type { Metadata } from "next";
import { Suspense } from "react";
import { RemoveMemberProvider } from "@/components/workspaces/settings/members/remove-member-provider";
import { RevokeInvitationProvider } from "@/components/workspaces/settings/members/revoke-invitation-provider";
import { WorkspaceMembers } from "@/components/workspaces/settings/members/workspace-members";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

export const metadata: Metadata = {
  title: "Members",
  description: "You can edit your workspace's members here.",
};

async function MembersContent(props: { params: Promise<unknown> }) {
  const params = await props.params;
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  return <WorkspaceMembers workspaceSlug={workspaceSlug} />;
}

export default async function WorkspaceTeamPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <RemoveMemberProvider>
        <RevokeInvitationProvider>
          <MembersContent params={props.params} />
        </RevokeInvitationProvider>
      </RemoveMemberProvider>
    </Suspense>
  );
}
