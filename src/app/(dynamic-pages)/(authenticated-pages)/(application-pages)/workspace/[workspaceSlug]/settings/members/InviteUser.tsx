"use client";


import { createInvitationHandler } from "@/data/user/invitation";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import type { Enum } from "@/types";
import { InviteOrganizationMemberDialog } from "./InviteOrganizationMemberDialog";

export function InviteUser({ organizationId }: { organizationId: string }) {
  const { mutate, isLoading } = useSAToastMutation(
    async ({
      email,
      role,
    }: {
      email: string;
      role: Enum<"organization_member_role">;
    }) => {
      return await createInvitationHandler({
        email,
        organizationId,
        role,
      });
    },
    {
      loadingMessage: "Inviting user...",
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to invite organization member ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to invite organization member';
        }
      },
      successMessage: "User invited!",
    },
  );

  return (
    <>
      <InviteOrganizationMemberDialog
        onInvite={(email, role) => {
          mutate({
            email,
            role,
          });
        }}
        isLoading={isLoading}
      />
    </>
  );
}
