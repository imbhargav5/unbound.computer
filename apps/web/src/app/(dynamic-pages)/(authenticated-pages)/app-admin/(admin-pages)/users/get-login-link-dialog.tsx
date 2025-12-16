"use client";
import { Link } from "lucide-react";
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
import { appAdminGetUserImpersonationUrlAction } from "@/data/admin/user";

export const GetLoginLinkDialog = ({ userId }: { userId: string }) => {
  const [open, setOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: getLoginLink, isPending } = useAction(
    appAdminGetUserImpersonationUrlAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Generating login link...");
      },
      onSuccess: ({ data }) => {
        if (data) {
          navigator.clipboard.writeText(data);
          toast.success("Login link copied to clipboard!", {
            id: toastRef.current,
          });
          toastRef.current = undefined;
        } else {
          throw new Error("Failed to generate login link");
        }
      },
      onError: ({ error }) => {
        const errorMessage =
          error.serverError ?? "Failed to generate login link";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    }
  );

  const handleGetLoginLink = () => {
    getLoginLink({ userId });
    setOpen(false);
  };

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button disabled={isPending} variant="ghost">
          Get login link
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <div className="mb-2 w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <Link className="h-6 w-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">Get Login Link</DialogTitle>
            <DialogDescription className="mt-0 text-base">
              Are you sure you want to generate a login link for the user?
            </DialogDescription>
          </div>
        </DialogHeader>
        <DialogFooter className="mt-2">
          <Button
            disabled={isPending}
            onClick={() => setOpen(false)}
            type="button"
            variant="outline"
          >
            Cancel
          </Button>
          <Button
            disabled={isPending}
            onClick={handleGetLoginLink}
            type="button"
            variant="default"
          >
            Get Login Link
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
