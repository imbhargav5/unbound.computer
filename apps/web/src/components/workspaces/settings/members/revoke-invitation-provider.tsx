// @/components/workspaces/settings/members/RevokeInvitationProvider.tsx
"use client";

import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { createContext, useContext, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { revokeInvitationAction } from "@/data/user/invitation";

type InvitationToRevoke = {
  invitationId: string;
};

type RevokeInvitationContextValue = {
  openRevokeDialog: (invitationId: string) => void;
};

const RevokeInvitationContext = createContext<
  RevokeInvitationContextValue | undefined
>(undefined);

export function useRevokeInvitation() {
  const context = useContext(RevokeInvitationContext);
  if (!context) {
    throw new Error(
      "useRevokeInvitation must be used within RevokeInvitationProvider"
    );
  }
  return context;
}

type RevokeInvitationProviderProps = {
  children: React.ReactNode;
};

export function RevokeInvitationProvider({
  children,
}: RevokeInvitationProviderProps) {
  const [invitationToRevoke, setInvitationToRevoke] =
    useState<InvitationToRevoke | null>(null);
  const [open, setOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: revokeInvitation, isPending: isRevoking } = useAction(
    revokeInvitationAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Revoking Invitation...");
      },
      onSuccess: () => {
        toast.success("Invitation revoked!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        setOpen(false);
        setInvitationToRevoke(null);
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to revoke invitation";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    }
  );

  const openRevokeDialog = (invitationId: string) => {
    setInvitationToRevoke({ invitationId });
    setOpen(true);
  };

  const handleRevoke = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (invitationToRevoke) {
      revokeInvitation({ invitationId: invitationToRevoke.invitationId });
    }
  };

  const handleClose = () => {
    setOpen(false);
    setInvitationToRevoke(null);
  };

  return (
    <RevokeInvitationContext.Provider value={{ openRevokeDialog }}>
      {children}
      <Dialog onOpenChange={setOpen} open={open}>
        <DialogContent className="hide-dialog-close sm:max-w-[425px]">
          <form onSubmit={handleRevoke}>
            <DialogHeader>
              <DialogTitle>Revoke Invitation</DialogTitle>
              <DialogDescription>
                Are you sure you want to revoke this invitation? This action is
                irreversible.
              </DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <input
                name="invitationId"
                type="hidden"
                value={invitationToRevoke?.invitationId ?? ""}
              />
              <Button
                aria-disabled={isRevoking}
                type="submit"
                variant="destructive"
              >
                {isRevoking ? "Revoking Invitation..." : "Yes, revoke"}
              </Button>
              <Button onClick={handleClose} type="button" variant="outline">
                Cancel
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </RevokeInvitationContext.Provider>
  );
}
