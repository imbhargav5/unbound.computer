"use client";

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
import { revokeUnkeyTokenAction } from "@/data/user/unkey";

type Props = {
  keyId: string;
};

export const ConfirmRevokeTokenDialog = ({ keyId }: Props) => {
  const [open, setOpen] = useState<boolean>(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute, status } = useAction(revokeUnkeyTokenAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Revoking API Key...");
    },
    onSuccess: () => {
      toast.success("API Key revoked!", { id: toastRef.current });
      toastRef.current = undefined;
      setOpen(false);
    },
    onError: ({ error }) => {
      console.log(error);
      const errorMessage = error.serverError ?? "Failed to revoke API Key";
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    execute({ keyId });
  };

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button>Revoke</Button>
      </DialogTrigger>
      <DialogContent className="hide-dialog-close sm:max-w-[425px]">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Revoke Token</DialogTitle>
            <DialogDescription>
              Are you sure you want to revoke this token? This action is
              irreversible.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <input name="keyId" type="hidden" value={keyId} />
            <Button
              disabled={status === "executing"}
              type="submit"
              variant="destructive"
            >
              {status === "executing" ? "Revoking API Key..." : "Yes, revoke"}
            </Button>
            <Button
              onClick={() => {
                setOpen(false);
              }}
              type="button"
              variant="outline"
            >
              Cancel
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
