import moment from "moment";
import type { Metadata } from "next";
import { Suspense } from "react";
import { T } from "@/components/ui/typography-ui";
import {
  getPendingInvitationsInWorkspace,
  getWorkspaceTeamMembers,
} from "@/data/user/workspaces";
import {
  getCachedLoggedInUserWorkspaceRole,
  getCachedWorkspaceBySlug,
} from "@/rsc-data/user/workspaces";
import type {
  TeamMembersTableProps,
  WorkspaceWithMembershipType,
} from "@/types";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import { InviteUser } from "./invite-user";
import { TeamInvitationsTable } from "./team-invitations-table";
import { TeamMembersTable } from "./team-members-table";

export const metadata: Metadata = {
  title: "Members",
  description: "You can edit your workspace's members here.",
};

async function TeamMembers({
  workspace,
}: {
  workspace: WorkspaceWithMembershipType;
}) {
  const members = await getWorkspaceTeamMembers(workspace.id);
  const user = await serverGetLoggedInUserClaims();
  const userId = user.sub;
  const workspaceRole = await getCachedLoggedInUserWorkspaceRole(workspace.id);
  const isWorkspaceAdmin =
    workspaceRole === "admin" || workspaceRole === "owner";
  const normalizedMembers: TeamMembersTableProps["members"] = members.map(
    (member, index) => {
      const userProfile = Array.isArray(member.user_profiles)
        ? member.user_profiles[0]
        : member.user_profiles;
      if (!userProfile) {
        throw new Error("User profile not found");
      }
      return {
        index: index + 1,
        id: userProfile.id,
        name: userProfile.full_name ?? `User ${userProfile.id}`,
        role: member.workspace_member_role,
        created_at: moment(member.added_at).format("DD MMM YYYY"),
      };
    }
  );

  return (
    <div className="max-w-4xl space-y-4">
      <div className="flex items-center justify-between">
        <T.H3>Team Members</T.H3>
        {isWorkspaceAdmin ? <InviteUser workspace={workspace} /> : null}
      </div>
      <TeamMembersTable
        currentUserId={userId}
        isWorkspaceAdmin={isWorkspaceAdmin}
        members={normalizedMembers}
        workspaceId={workspace.id}
      />
    </div>
  );
}

async function TeamInvitations({
  workspace,
}: {
  workspace: WorkspaceWithMembershipType;
}) {
  const [invitations, workspaceRole] = await Promise.all([
    getPendingInvitationsInWorkspace(workspace.id),
    getCachedLoggedInUserWorkspaceRole(workspace.id),
  ]);
  const normalizedInvitations = invitations.map((invitation, index) => ({
    index: index + 1,
    id: invitation.id,
    email: invitation.invitee_user_email,
    created_at: moment(invitation.created_at).format("DD MMM YYYY"),
    status: invitation.status,
  }));

  if (!normalizedInvitations.length) {
    return (
      <div className="max-w-4xl space-y-4">
        <T.H3>Invitations</T.H3>
        <T.Subtle>No pending invitations</T.Subtle>
      </div>
    );
  }

  const isWorkspaceAdmin =
    workspaceRole === "admin" || workspaceRole === "owner";

  return (
    <div className="max-w-4xl space-y-4">
      <T.H3>Invitations</T.H3>
      <TeamInvitationsTable
        invitations={normalizedInvitations}
        isWorkspaceAdmin={isWorkspaceAdmin}
      />
    </div>
  );
}

export async function WorkspaceMembers({
  workspaceSlug,
}: {
  workspaceSlug: string;
}) {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return (
    <div className="space-y-12">
      <Suspense fallback={<T.Subtle>Loading team members...</T.Subtle>}>
        <TeamMembers workspace={workspace} />
      </Suspense>
      <Suspense fallback={<T.Subtle>Loading team invitations...</T.Subtle>}>
        <TeamInvitations workspace={workspace} />
      </Suspense>
    </div>
  );
}
