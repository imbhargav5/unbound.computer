import { T } from "@/components/ui/Typography";
import { Card } from "@/components/ui/card";
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

import { getPendingInvitationsInWorkspace, getWorkspaceTeamMembers } from "@/data/user/workspaces";
import { getCachedLoggedInUserWorkspaceRole, getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import type { TeamMembersTableProps, WorkspaceWithMembershipType } from "@/types";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import moment from "moment";
import type { Metadata } from "next";
import { Suspense } from "react";
import ProjectsTableLoadingFallback from "../../projects/loading";
import { InviteUser } from "./InviteUser";
import { RevokeInvitationDialog } from "./RevokeInvitationDialog";

export const metadata: Metadata = {
  title: "Members",
  description: "You can edit your workspace's members here.",
};

async function TeamMembers({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  const members = await getWorkspaceTeamMembers(workspace.id);
  const workspaceRole =
    await getCachedLoggedInUserWorkspaceRole(workspace.id);
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
        role: member.role,
        created_at: moment(member.added_at).format("DD MMM YYYY"),
      };
    },
  );

  return (
    <div className="space-y-4 max-w-4xl">
      <div className="flex justify-between items-center">
        <T.H3 className="mt-0">Team Members</T.H3>
        {isWorkspaceAdmin ? (
          <InviteUser workspace={workspace} />
        ) : null}
      </div>

      <Card>
        <ShadcnTable data-testid="members-table">
          <TableHeader>
            <TableRow>
              <TableHead> # </TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Role</TableHead>
              <TableHead>Joined On</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {normalizedMembers.map((member, index) => {
              return (
                <TableRow data-user-id={member.id} key={member.id}>
                  <TableCell>{index + 1}</TableCell>
                  <TableCell data-testid={"member-name"}>
                    {member.name}
                  </TableCell>
                  <TableCell data-testid={"member-role"} className="capitalize">
                    {member.role}
                  </TableCell>
                  <TableCell>{member.created_at}</TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </ShadcnTable>
      </Card>
    </div>
  );
}

async function TeamInvitations({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  const [invitations, workspaceRole] = await Promise.all([
    getPendingInvitationsInWorkspace(workspace.id),
    getCachedLoggedInUserWorkspaceRole(workspace.id),
  ]);
  const normalizedInvitations = invitations.map((invitation, index) => {
    return {
      index: index + 1,
      id: invitation.id,
      email: invitation.invitee_user_email,
      created_at: moment(invitation.created_at).format("DD MMM YYYY"),
      status: invitation.status,
    };
  });

  if (!normalizedInvitations.length) {
    return (
      <div className="space-y-4 max-w-4xl">
        <T.H3>Invitations</T.H3>
        <T.Subtle>No pending invitations</T.Subtle>
      </div>
    );
  }

  return (
    <div className="space-y-4 max-w-4xl">
      <T.H3>Invitations</T.H3>
      <div className="shadow-sm border rounded-lg overflow-hidden">
        <ShadcnTable>
          <TableHeader>
            <TableRow>
              <TableHead scope="col"> # </TableHead>
              <TableHead scope="col">Email</TableHead>
              <TableHead scope="col">Sent On</TableHead>
              <TableHead scope="col">Status</TableHead>
              {workspaceRole === "admin" || workspaceRole === "owner" ? (
                <TableHead scope="col">Actions</TableHead>
              ) : null}
            </TableRow>
          </TableHeader>
          <TableBody>
            {normalizedInvitations.map((invitation, index) => {
              return (
                <TableRow key={invitation.id}>
                  <TableCell>{index + 1}</TableCell>
                  <TableCell>{invitation.email}</TableCell>
                  <TableCell>{invitation.created_at}</TableCell>
                  <TableCell className="uppercase">
                    <span>
                      {invitation.status === "active"
                        ? "pending"
                        : invitation.status}
                    </span>
                  </TableCell>
                  {workspaceRole === "admin" ||
                    workspaceRole === "owner" ? (
                    <TableCell>
                      <RevokeInvitationDialog invitationId={invitation.id} />
                    </TableCell>
                  ) : null}
                </TableRow>
              );
            })}
          </TableBody>
        </ShadcnTable>
      </div>
    </div>
  );
}

export default async function WorkspaceTeamPage({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return (
    <div className="space-y-12">
      <Suspense fallback={<ProjectsTableLoadingFallback />}>
        <TeamMembers workspace={workspace} />
      </Suspense>
      <Suspense fallback={<ProjectsTableLoadingFallback />}>
        <TeamInvitations workspace={workspace} />
      </Suspense>
    </div>
  );
}
