"use client";

import { useHookFormActionErrorMapper } from "@next-cool-action/adapter-react-hook-form/hooks";
import { Check, Loader, UserPlus } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { useForm } from "react-hook-form";
import { useTimeoutWhen } from "rooks";
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
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { WorkspaceMemberRoleSelect } from "@/components/workspace-member-role-select";
import { createInvitationAction } from "@/data/user/invitation";
import { zodResolver } from "@/lib/zod-resolver";
import type { WorkspaceWithMembershipType } from "@/types";
import { invitationRoleEnum } from "@/utils/zod-schemas/enums/invitations";

const inviteUserSchema = z.object({
  email: z.string().email("Please enter a valid email"),
  role: invitationRoleEnum,
});

type InviteUserFormData = z.infer<typeof inviteUserSchema>;

export function InviteUser({
  workspace,
}: {
  workspace: WorkspaceWithMembershipType;
}) {
  const toastRef = useRef<string | number | undefined>(undefined);
  const [open, setOpen] = useState(false);

  const { execute, status, reset, result } = useAction(createInvitationAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Inviting user...");
    },
    onSuccess: () => {
      toast.success("User invited!", { id: toastRef.current });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      const errorMessage = error.serverError || "Failed to invite user";
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof inviteUserSchema
  >(result.validationErrors, { joinBy: "\n" });

  const form = useForm<InviteUserFormData>({
    resolver: zodResolver(inviteUserSchema),
    defaultValues: {
      email: "",
      role: "member",
    },
    errors: hookFormValidationErrors,
  });

  const closeDialog = () => {
    setOpen(false);
    form.reset();
  };

  const hasSettled = status === "hasSucceeded" || status === "hasErrored";
  useTimeoutWhen(
    () => {
      reset();
      closeDialog();
    },
    1500,
    hasSettled
  );

  const onSubmit = (data: InviteUserFormData) => {
    execute({
      email: data.email,
      workspaceId: workspace.id,
      role: data.role,
    });
  };

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button
          data-testid="invite-user-button"
          size="default"
          variant="default"
        >
          <UserPlus className="mr-2 h-5 w-5" />
          Invite user
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <div className="mb-2 w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <UserPlus className="h-6 w-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">Invite user</DialogTitle>
            <DialogDescription className="mt-0 text-base">
              Invite a user to your workspace.
            </DialogDescription>
          </div>
        </DialogHeader>
        <Form {...form}>
          <form
            data-testid="invite-user-form"
            onSubmit={form.handleSubmit(onSubmit)}
          >
            <div className="mb-8 space-y-4">
              <FormField
                control={form.control}
                name="role"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel className="text-muted-foreground">
                      Select a role
                    </FormLabel>
                    <FormControl>
                      <WorkspaceMemberRoleSelect
                        onChange={field.onChange}
                        value={field.value}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="email"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel className="text-muted-foreground">
                      Enter Email
                    </FormLabel>
                    <FormControl>
                      <Input
                        className="h-11 w-full appearance-none rounded-lg border px-3 py-2 text-base leading-tight shadow-sm focus:shadow-outline focus:outline-hidden focus:ring-0"
                        disabled={status !== "idle"}
                        placeholder="Email"
                        type="email"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>
            <DialogFooter>
              <Button
                onClick={() => {
                  setOpen(false);
                }}
                type="button"
                variant="outline"
              >
                Cancel
              </Button>
              <Button
                disabled={status !== "idle"}
                type="submit"
                variant="default"
              >
                {status === "executing" ? (
                  <>
                    <Loader className="mr-2 h-4 w-4 animate-spin" />
                    Inviting...
                  </>
                ) : status === "hasSucceeded" ? (
                  <>
                    <Check className="mr-2 h-4 w-4" />
                    Invited!
                  </>
                ) : (
                  "Invite"
                )}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
