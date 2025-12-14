// @/components/workspaces/settings/members/TeamInvitationsTable.tsx
"use client";

import { Trash } from "lucide-react";
import type React from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useRevokeInvitation } from "./revoke-invitation-provider";

type TeamInvitationsTableProps = {
  invitations: Array<{
    index: number;
    id: string;
    email: string;
    created_at: string;
    status: string;
  }>;
  isWorkspaceAdmin: boolean;
};

export const TeamInvitationsTable: React.FC<TeamInvitationsTableProps> = ({
  invitations,
  isWorkspaceAdmin,
}) => {
  const { openRevokeDialog } = useRevokeInvitation();

  return (
    <ShadcnTable>
      <TableHeader>
        <TableRow>
          <TableHead scope="col"> # </TableHead>
          <TableHead scope="col">Email</TableHead>
          <TableHead scope="col">Sent On</TableHead>
          <TableHead scope="col">Status</TableHead>
          {isWorkspaceAdmin ? <TableHead scope="col">Actions</TableHead> : null}
        </TableRow>
      </TableHeader>
      <TableBody>
        {invitations.map((invitation, index) => (
          <TableRow
            data-invitation-email={invitation.email}
            data-testid={`invitation-row-${invitation.email}`}
            key={invitation.id}
          >
            <TableCell>{index + 1}</TableCell>
            <TableCell>{invitation.email}</TableCell>
            <TableCell>{invitation.created_at}</TableCell>
            <TableCell className="uppercase">
              <Badge
                variant={
                  invitation.status === "active" ? "secondary" : "default"
                }
              >
                {invitation.status === "active" ? "pending" : invitation.status}
              </Badge>
            </TableCell>
            {isWorkspaceAdmin ? (
              <TableCell>
                <Button
                  onClick={() => openRevokeDialog(invitation.id)}
                  size="icon"
                  variant="outline"
                >
                  <Trash className="size-4" />
                </Button>
              </TableCell>
            ) : null}
          </TableRow>
        ))}
      </TableBody>
    </ShadcnTable>
  );
};
