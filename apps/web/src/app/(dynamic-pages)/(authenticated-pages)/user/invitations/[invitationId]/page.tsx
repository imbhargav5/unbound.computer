import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";
import { Skeleton } from "@/components/ui/skeleton";
import { getInvitationById } from "@/data/user/invitation";
import type { DBTable } from "@/types";
import { InvitationContent } from "./invitation-content";

const paramsSchema = z.object({
  invitationId: z.string(),
});

async function Invitation({ invitationId }: { invitationId: string }) {
  try {
    const invitation = await getInvitationById(invitationId);

    const inviter = Array.isArray(invitation.inviter)
      ? invitation.inviter[0]
      : invitation.inviter;
    const workspace = Array.isArray(invitation.workspace)
      ? (invitation.workspace[0] as DBTable<"workspaces"> | null)
      : invitation.workspace;

    if (!(workspace && inviter)) {
      throw new Error("Workspace or Inviter not found");
    }

    return (
      <InvitationContent
        invitationId={invitation.id}
        inviteeRole={invitation.invitee_user_role}
        inviterName={inviter.full_name || `User ${inviter.id}`}
        status={invitation.status}
        workspaceName={workspace.name}
      />
    );
  } catch (error) {
    return notFound();
  }
}

async function InvitationPageContent(props: { params: Promise<unknown> }) {
  const params = await props.params;
  const { invitationId } = paramsSchema.parse(params);
  return (
    <Suspense fallback={<Skeleton className="h-6 w-16" />}>
      <Invitation invitationId={invitationId} />
    </Suspense>
  );
}

export default async function InvitationPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <InvitationPageContent params={props.params} />
    </Suspense>
  );
}
