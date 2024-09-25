"use client";

import { createInvitationAction } from "@/data/user/invitation";
import type { Enum, WorkspaceWithMembershipType } from "@/types";
import { useAction } from 'next-safe-action/hooks';
import { useRef } from 'react';
import { toast } from 'sonner';
import { InviteWorkspaceMemberDialog } from "./InviteWorkspaceMemberDialog";


export function InviteUser({ workspace }: { workspace: WorkspaceWithMembershipType }): JSX.Element {
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute, status } = useAction(createInvitationAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Inviting user...');
    },
    onSuccess: () => {
      toast.success('User invited!', { id: toastRef.current });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      let errorMessage: string;
      try {
        if (error instanceof Error) {
          errorMessage = error.message;
        } else {
          errorMessage = `Failed to invite organization member: ${String(error)}`;
        }
      } catch (_err) {
        errorMessage = 'Failed to invite organization member';
      }
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const handleInvite = (email: string, role: Exclude<Enum<"workspace_user_role">, "owner">) => {
    execute({
      email,
      workspaceId: workspace.id,
      role,
    });
  };

  return (
    <InviteWorkspaceMemberDialog
      onInvite={handleInvite}
      isLoading={status === 'executing'}
    />
  );
}
