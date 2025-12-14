// @/components/workspaces/settings/members/RemoveMemberProvider.tsx
"use client";

import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { createContext, useContext, useState } from "react";
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
import { Input } from "@/components/ui/input";
import { removeWorkspaceMemberAction } from "@/data/user/workspaces";

type MemberToRemove = {
  workspaceId: string;
  memberId: string;
  memberName: string;
};

type RemoveMemberContextValue = {
  openRemoveDialog: (
    workspaceId: string,
    memberId: string,
    memberName: string
  ) => void;
};

const RemoveMemberContext = createContext<RemoveMemberContextValue | undefined>(
  undefined
);

export function useRemoveMember() {
  const context = useContext(RemoveMemberContext);
  if (!context) {
    throw new Error("useRemoveMember must be used within RemoveMemberProvider");
  }
  return context;
}

type RemoveMemberProviderProps = {
  children: React.ReactNode;
};

export function RemoveMemberProvider({ children }: RemoveMemberProviderProps) {
  const [memberToRemove, setMemberToRemove] = useState<MemberToRemove | null>(
    null
  );
  const [open, setOpen] = useState(false);
  const [confirmText, setConfirmText] = useState("");

  const { execute: removeMember, isPending } = useAction(
    removeWorkspaceMemberAction,
    {
      onSuccess: () => {
        toast.success("Member removed successfully");
        setOpen(false);
        setMemberToRemove(null);
        setConfirmText("");
      },
      onError: ({ error }) => {
        toast.error(error.serverError || "Failed to remove member");
      },
    }
  );

  const openRemoveDialog = (
    workspaceId: string,
    memberId: string,
    memberName: string
  ) => {
    setMemberToRemove({ workspaceId, memberId, memberName });
    setOpen(true);
    setConfirmText("");
  };

  const handleRemove = () => {
    if (memberToRemove) {
      removeMember({
        workspaceId: memberToRemove.workspaceId,
        memberId: memberToRemove.memberId,
      });
    }
  };

  const handleClose = () => {
    setOpen(false);
    setMemberToRemove(null);
    setConfirmText("");
  };

  const isConfirmed = confirmText === memberToRemove?.memberName;

  return (
    <RemoveMemberContext.Provider value={{ openRemoveDialog }}>
      {children}
      <Dialog onOpenChange={setOpen} open={open}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Remove Team Member</DialogTitle>
            <DialogDescription>
              Are you sure you want to remove {memberToRemove?.memberName} from
              the team? This action cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <div className="py-4">
            <Input
              onChange={(e) => setConfirmText(e.target.value)}
              placeholder={`Type "${memberToRemove?.memberName}" to confirm`}
              value={confirmText}
            />
          </div>
          <DialogFooter>
            <Button onClick={handleClose} variant="outline">
              Cancel
            </Button>
            <Button
              disabled={!isConfirmed || isPending}
              onClick={handleRemove}
              variant="destructive"
            >
              {isPending ? "Removing..." : "Remove Member"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </RemoveMemberContext.Provider>
  );
}
