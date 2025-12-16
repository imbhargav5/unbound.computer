"use client";
import { Plus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { useInput } from "rooks";
import { toast } from "sonner";
import { z } from "zod";
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
import { Label } from "@/components/ui/label";
import { createUserAction } from "@/data/admin/user";
import { getErrorMessage } from "@/utils/get-error-message";

export const AppAdminCreateUserDialog = () => {
  const emailInput = useInput("");
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: createUser, isPending: isCreatingUser } = useAction(
    createUserAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Creating user...");
      },
      onSuccess: () => {
        toast.success("User created!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        setOpen(false);
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to create user";
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
        <Button variant="default">
          <Plus className="mr-2" /> Create User
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <div className="w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <Plus className="h-6 w-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">Create User</DialogTitle>
            <DialogDescription className="text-base">
              Create a new user by entering their email address.
            </DialogDescription>
          </div>
        </DialogHeader>
        <div className="grid gap-4">
          <Label className="space-y-2">
            <span>Email</span>
            <Input name="email" type="email" {...emailInput} />
          </Label>
        </div>
        <DialogFooter className="mt-8">
          <Button
            aria-disabled={isCreatingUser}
            onClick={() => {
              try {
                const validEmail = z.email().parse(emailInput.value);
                createUser({ email: validEmail });
              } catch (error) {
                const message = getErrorMessage(error);
                toast.error(message);
              }
            }}
            type="button"
          >
            {isCreatingUser ? "Loading..." : "Create User"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
