import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { T } from "@/components/ui/typography-ui";
import { getPendingInvitationsOfUser } from "@/data/user/invitation";
import type { Enum } from "@/types";

const PendingInvitationsTable = ({
  pendingInvitationsList,
}: {
  pendingInvitationsList: Array<{
    id: string;
    inviterUserFullName: string;
    organizationTitle: string;
    status: Enum<"workspace_invitation_link_status">;
    role: Enum<"workspace_member_role_type">;
    organizationId: string;
  }>;
}) => (
  <div className="space-y-2">
    <T.P>You have {pendingInvitationsList.length} pending invitations</T.P>
    <ShadcnTable>
      <TableHeader>
        <TableRow>
          <TableHead scope="col">#</TableHead>
          <TableHead scope="col">Invited By</TableHead>
          <TableHead scope="col">Organization Name</TableHead>
          <TableHead scope="col">ROLE</TableHead>
          <TableHead scope="col">Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {pendingInvitationsList.map((invitation, index) => (
          <TableRow
            data-invitation-id={invitation.id}
            data-organization-id={invitation.organizationId}
            key={invitation.id}
          >
            <TableCell>{index + 1}</TableCell>
            <TableCell className="text-left">
              {invitation.inviterUserFullName}
            </TableCell>
            <TableCell>{invitation.organizationTitle}</TableCell>
            <TableCell>{invitation.role}</TableCell>
            <TableCell>
              <div className="flex space-x-2">                
                  <Button
                    asChild
                    data-invitation-id={invitation.id}
                    size="default"
                    variant="default"
                  >
                    <Link href={`/user/invitations/${invitation.id}`}>View Invitation</Link>
                </Button>
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </ShadcnTable>
  </div>
);

export const PendingInvitationsList = async () => {
  const pendingInvitations = await getPendingInvitationsOfUser();

  const pendingInvitationsList = pendingInvitations
    .map((invitation) => ({
      id: invitation.id,
      inviterUserFullName:
        invitation.inviter.full_name ?? invitation.invitee_user_email,
      organizationTitle: invitation.workspace.name,
      status: invitation.status,
      role: invitation.invitee_user_role,
      organizationId: invitation.workspace.id,
    }))
    .filter(Boolean);
  return (
    <>
      {pendingInvitationsList.length > 0 ? (
        <PendingInvitationsTable
          pendingInvitationsList={pendingInvitationsList}
        />
      ) : (
        <T.Subtle>You have no pending invitations.</T.Subtle>
      )}
    </>
  );
};
