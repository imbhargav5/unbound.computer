"use client";
import { Send } from "lucide-react";
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
import { sendLoginLinkAction } from "@/data/admin/user";

export const ConfirmSendLoginLinkDialog = ({
  userEmail,
}: {
  userEmail: string;
}) => {
  const [open, setOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: sendLoginLink, isPending: isSending } = useAction(
    sendLoginLinkAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Sending login link...");
      },
      onSuccess: () => {
        toast.success("Login link sent!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        setOpen(false);
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to send login link";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    }
  );

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button aria-disabled={isSending} variant={"ghost"}>
          Send login link
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <div className="mb-2 w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <Send className="h-6 w-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">Send Login Link</DialogTitle>
            <DialogDescription className="mt-0 text-base">
              Are you sure you want to send a login link to the user?
            </DialogDescription>
          </div>
        </DialogHeader>
        <DialogFooter className="mt-2">
          <Button
            aria-disabled={isSending}
            onClick={() => {
              setOpen(false);
            }}
            type="button"
            variant="outline"
          >
            Cancel
          </Button>
          <Button
            aria-disabled={isSending}
            onClick={() => {
              sendLoginLink({ email: userEmail });
            }}
            type="button"
            variant="default"
          >
            Send Login Link
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
