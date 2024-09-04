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
import {
  getLoggedInUserOrganizationRole,
  getOrganizationIdBySlug,
  getPendingInvitationsInOrganization,
  getTeamMembersInOrganization,
} from "@/data/user/organizations";
import type { TeamMembersTableProps } from "@/types";
import { organizationSlugParamSchema } from "@/utils/zod-schemas/params";
import moment from "moment";
import type { Metadata } from "next";
import { Suspense } from "react";
import ProjectsTableLoadingFallback from "../../projects/loading";
import { InviteUser } from "./InviteUser";
import { RevokeInvitationDialog } from "./RevokeInvitationDialog";

export const metadata: Metadata = {
  title: "Members",
  description: "You can edit your organization's members here.",
};

async function TeamMembers({ organizationId }: { organizationId: string }) {
  const members = await getTeamMembersInOrganization(organizationId);
  const organizationRole =
    await getLoggedInUserOrganizationRole(organizationId);
  const isOrganizationAdmin =
    organizationRole === "admin" || organizationRole === "owner";
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
        role: member.member_role,
        created_at: moment(member.created_at).format("DD MMM YYYY"),
      };
    },
  );

  return (
    <div className="space-y-4 max-w-4xl">
      <div className="flex justify-between items-center">
        <T.H3 className="mt-0">Team Members</T.H3>
        {isOrganizationAdmin ? (
          <InviteUser organizationId={organizationId} />
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

async function TeamInvitations({ organizationId }: { organizationId: string }) {
  const [invitations, organizationRole] = await Promise.all([
    getPendingInvitationsInOrganization(organizationId),
    getLoggedInUserOrganizationRole(organizationId),
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
              {organizationRole === "admin" || organizationRole === "owner" ? (
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
                  {organizationRole === "admin" ||
                    organizationRole === "owner" ? (
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

export default async function OrganizationPage({
  params,
}: {
  params: unknown;
}) {
  const { organizationSlug } = organizationSlugParamSchema.parse(params);
  const organizationId = await getOrganizationIdBySlug(organizationSlug);
  return (
    <div className="space-y-12">
      <Suspense fallback={<ProjectsTableLoadingFallback />}>
        <TeamMembers organizationId={organizationId} />
      </Suspense>
      <Suspense fallback={<ProjectsTableLoadingFallback />}>
        <TeamInvitations organizationId={organizationId} />
      </Suspense>
    </div>
  );
}
