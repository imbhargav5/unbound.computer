"use client";
import { zodResolver } from "@hookform/resolvers/zod";
import { CheckCheck, Network } from "lucide-react";
import { useForm } from "react-hook-form";
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
import { Label } from "@/components/ui/label";
import { useCreateWorkspaceDialog } from "@/hooks/use-create-workspace-dialog";
import { useSafeShortcut } from "@/hooks/use-safe-shortcut";
import { generateWorkspaceSlug } from "@/lib/utils";
import {
  type CreateWorkspaceFormSchema,
  createWorkspaceFormSchema,
} from "@/utils/zod-schemas/workspaces";

export function CreateWorkspaceDialog() {
  const {
    isOpen,
    openDialog,
    closeDialog,
    toggleDialog,
    createWorkspaceActionHelpers,
  } = useCreateWorkspaceDialog();

  const {
    execute: createWorkspaceExecute,
    isPending,
    hasSucceeded,
    reset: resetSafeAction,
  } = createWorkspaceActionHelpers;

  // Keyboard shortcut "w" to toggle dialog
  useSafeShortcut("w", (event) => {
    event.preventDefault();
    event.stopPropagation();
    if (!isOpen) {
      openDialog();
    }
  });

  const onSubmit = (data: CreateWorkspaceFormSchema) => {
    createWorkspaceExecute({
      name: data.name,
      slug: data.slug,
      workspaceType: "team",
      isOnboardingFlow: false,
    });
  };

  const {
    register,
    formState: { errors },
    handleSubmit,
    setValue,
    reset: resetForm,
  } = useForm<CreateWorkspaceFormSchema>({
    resolver: zodResolver(createWorkspaceFormSchema),
    defaultValues: {
      name: "",
      slug: "",
    },
  });

  return (
    <Dialog
      data-testid="create-workspace-dialog"
      onOpenChange={(open) => {
        if (!open) closeDialog();
      }}
      open={isOpen}
    >
      <DialogContent>
        <DialogHeader>
          <div className="mb-2 w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <Network className="h-6 w-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">Create Workspace</DialogTitle>
            <DialogDescription className="mt-0 text-base">
              Create a new workspace and get started.
            </DialogDescription>
          </div>
        </DialogHeader>
        <form
          data-testid="create-workspace-form"
          onSubmit={handleSubmit(onSubmit)}
        >
          <div className="mb-8 space-y-2">
            <div>
              <Label>Workspace Name</Label>
              <Input
                {...register("name")}
                className="mt-1.5 h-11 w-full appearance-none rounded-lg border px-3 py-2 text-base leading-tight shadow-sm focus:shadow-outline focus:outline-hidden focus:ring-0"
                data-testid="workspace-name-input"
                disabled={isPending}
                id="name"
                onChange={(e) => {
                  setValue("slug", generateWorkspaceSlug(e.target.value), {
                    shouldValidate: true,
                  });
                  setValue("name", e.target.value, { shouldValidate: true });
                }}
                placeholder="Workspace Name"
                type="text"
              />
            </div>

            <div>
              <Label>Workspace Slug</Label>
              <Input
                {...register("slug")}
                className="mt-1.5 h-11 w-full appearance-none rounded-lg border px-3 py-2 text-base leading-tight shadow-sm focus:shadow-outline focus:outline-hidden focus:ring-0"
                data-testid="workspace-slug-input"
                disabled={isPending}
                id="slug"
                placeholder="Workspace Slug"
                type="text"
              />
            </div>
          </div>

          <DialogFooter>
            <Button
              disabled={isPending}
              onClick={closeDialog}
              type="button"
              variant="outline"
            >
              Cancel
            </Button>
            <Button
              data-testid="create-workspace-submit-button"
              disabled={isPending}
              type="submit"
              variant="default"
            >
              {hasSucceeded ? (
                <>
                  <CheckCheck className="size-4" /> Workspace Created!
                </>
              ) : isPending ? (
                "Creating Workspace..."
              ) : (
                "Create Workspace"
              )}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
