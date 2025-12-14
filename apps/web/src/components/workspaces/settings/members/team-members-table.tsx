// @/components/workspaces/settings/members/TeamMembersTable.tsx
"use client";

import { MoreHorizontal, UserMinus } from "lucide-react";
import type React from "react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { TeamMembersTableProps } from "@/types";
import { EditMemberRoleDialog } from "./edit-member-role-dialog";
import {
  type LeaveWorkspaceConditions,
  LeaveWorkspaceDialog,
} from "./leave-workspace-dialog";
import { useRemoveMember } from "./remove-member-provider";

type TeamMembersTableComponentProps = {
  members: TeamMembersTableProps["members"];
  workspaceId: string;
  currentUserId: string;
  isWorkspaceAdmin: boolean;
};

export const TeamMembersTable: React.FC<TeamMembersTableComponentProps> = ({
  members,
  workspaceId,
  currentUserId,
  isWorkspaceAdmin,
}) => {
  const { openRemoveDialog } = useRemoveMember();

  return (
    <ShadcnTable data-testid="members-table">
      <TableHeader>
        <TableRow>
          <TableHead> # </TableHead>
          <TableHead>Name</TableHead>
          <TableHead>Role</TableHead>
          <TableHead>Joined On</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {members.map((member, index) => {
          const isMemberCurrentUser = member.id === currentUserId;
          const shouldShowActions = isWorkspaceAdmin || isMemberCurrentUser;

          const isLastAdmin =
            isWorkspaceAdmin &&
            members.filter((m) => m.role === "admin" || m.role === "owner")
              .length === 1;

          const leaveConditions: LeaveWorkspaceConditions =
            isWorkspaceAdmin && isLastAdmin
              ? "DISABLED_IS_LAST_ADMIN"
              : "ENABLED";

          return (
            <TableRow data-user-id={member.id} key={member.id}>
              <TableCell>{index + 1}</TableCell>
              <TableCell data-testid="member-name">{member.name}</TableCell>
              <TableCell className="capitalize" data-testid="member-role">
                {member.role}
              </TableCell>
              <TableCell>{member.created_at}</TableCell>
              <TableCell>
                {shouldShowActions ? (
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button className="h-8 w-8 p-0" variant="ghost">
                        <span className="sr-only">Open menu</span>
                        <MoreHorizontal className="h-4 w-4" />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      {isWorkspaceAdmin && member.id !== currentUserId && (
                        <>
                          <EditMemberRoleDialog
                            currentRole={member.role}
                            memberId={member.id}
                            workspaceId={workspaceId}
                          />
                          <DropdownMenuItem
                            onSelect={() =>
                              openRemoveDialog(
                                workspaceId,
                                member.id,
                                member.name ?? `Member ${member.id}`
                              )
                            }
                          >
                            <UserMinus className="mr-2 h-4 w-4" />
                            <span>Remove from Team</span>
                          </DropdownMenuItem>
                        </>
                      )}
                      {member.id === currentUserId && (
                        <LeaveWorkspaceDialog
                          leaveConditions={leaveConditions}
                          memberId={member.id}
                          workspaceId={workspaceId}
                        />
                      )}
                    </DropdownMenuContent>
                  </DropdownMenu>
                ) : null}
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </ShadcnTable>
  );
};
