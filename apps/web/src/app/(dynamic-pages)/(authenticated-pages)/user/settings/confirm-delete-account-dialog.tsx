"use client";

import { Trash } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { T } from "@/components/ui/typography-ui";
import { requestAccountDeletionAction } from "@/data/user/user";
import { ConfirmDeletionViaEmailDialog } from "./confirm-deletion-via-email-dialog";

export const ConfirmDeleteAccountDialog = () => {
  const [open, setOpen] = useState(false);
  const [isSuccessDialogOpen, setIsSuccessDialogOpen] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const isDisabled = confirmText !== "delete";
  const toastRef = useRef<string | number | undefined>(undefined);

  const {
    execute: requestAccountDeletion,
    isPending: isRequestingAccountDeletion,
  } = useAction(requestAccountDeletionAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Creating deletion request...");
    },
    onSuccess: () => {
      toast.success(
        "Account deletion request created. Please check your email.",
        {
          id: toastRef.current,
        }
      );
      toastRef.current = undefined;
      setIsSuccessDialogOpen(true);
    },
    onError: ({ error }) => {
      const errorMessage = error.serverError ?? "Failed!";
      toast.error(errorMessage, {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
  });

  return (
    <>
      <Dialog onOpenChange={setOpen} open={open}>
        <DialogTrigger asChild>
          <Button variant="destructive">
            <Trash className="mr-2 h-5 w-5" /> Delete Account
          </Button>
        </DialogTrigger>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle>Delete Account</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete your account? This action is
              irreversible. All your data will be lost.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Input
              className="mt-4"
              onChange={(e) => setConfirmText(e.target.value)}
              value={confirmText}
            />
            <T.Subtle className="pl-2">
              Type &quot;delete&quot; into the input to confirm.
            </T.Subtle>
          </div>
          <DialogFooter>
            <Button onClick={() => setOpen(false)} variant="outline">
              Cancel
            </Button>
            <Button
              disabled={isDisabled || isRequestingAccountDeletion}
              onClick={() => {
                requestAccountDeletion();
                setOpen(false);
              }}
              variant="destructive"
            >
              {isRequestingAccountDeletion ? "Deleting..." : "Delete"} Account
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <ConfirmDeletionViaEmailDialog
        open={isSuccessDialogOpen}
        setOpen={setIsSuccessDialogOpen}
      />
    </>
  );
};
