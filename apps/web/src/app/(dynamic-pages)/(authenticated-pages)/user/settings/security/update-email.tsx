// src/app/(dynamic-pages)/(authenticated-pages)/user/settings/security/UpdateEmail.tsx

"use client";
import { useAction } from "next-cool-action/hooks";
import { useRef } from "react";
import { useInput } from "rooks";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { updateEmailAction } from "@/data/user/security";
import { classNames } from "@/utils/class-names";

export const UpdateEmail = ({
  initialEmail,
}: {
  initialEmail?: string | undefined;
}) => {
  const emailInput = useInput(initialEmail ?? "");
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: updateEmail, isPending } = useAction(updateEmailAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Updating email...");
    },
    onSuccess: () => {
      toast.success("Email updated!", {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      const errorMessage = error.serverError ?? "Failed to update email";
      toast.error(errorMessage, {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
  });

  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <Label className="text-muted-foreground" htmlFor="email">
          Email
        </Label>
        <div>
          <input
            autoComplete="email"
            id="email"
            name="email"
            required
            type="email"
            {...emailInput}
            className="block h-10 w-full appearance-none rounded-md border bg-gray-50/10 px-3 py-3 placeholder-muted-foreground shadow-xs focus:border-blue-500 focus:outline-hidden focus:ring-blue-500 sm:text-sm dark:bg-gray-800/20"
          />
        </div>
        <Button
          aria-disabled={isPending}
          className={classNames(
            "flex w-full justify-center rounded-lg border border-transparent px-4 py-3 font-medium text-sm text-white shadow-xs focus:outline-hidden focus:ring-2 focus:ring-offset-2 dark:text-black",
            isPending
              ? "bg-yellow-300 dark:bg-yellow-700"
              : "bg-black hover:bg-gray-900 dark:bg-white dark:hover:bg-gray-100"
          )}
          onClick={() => {
            updateEmail({ email: emailInput.value });
          }}
          type="button"
        >
          {isPending ? "Updating..." : "Update Email"}
        </Button>
      </div>
    </div>
  );
};
