// @/app/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/changelog/DeleteChangelogProvider.tsx
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
import { deleteChangelogAction } from "@/data/admin/marketing-changelog";

type ChangelogToDelete = {
  id: string;
  title: string;
};

type DeleteChangelogContextValue = {
  openDeleteDialog: (changelogId: string, changelogTitle: string) => void;
};

const DeleteChangelogContext = createContext<
  DeleteChangelogContextValue | undefined
>(undefined);

export function useDeleteChangelog() {
  const context = useContext(DeleteChangelogContext);
  if (!context) {
    throw new Error(
      "useDeleteChangelog must be used within DeleteChangelogProvider"
    );
  }
  return context;
}

type DeleteChangelogProviderProps = {
  children: React.ReactNode;
};

export function DeleteChangelogProvider({
  children,
}: DeleteChangelogProviderProps) {
  const [changelogToDelete, setChangelogToDelete] =
    useState<ChangelogToDelete | null>(null);
  const [open, setOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const deleteMutation = useAction(deleteChangelogAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Deleting changelog...", {
        description: "Please wait while we delete the changelog.",
      });
    },
    onSuccess: () => {
      toast.success("Changelog deleted successfully", { id: toastRef.current });
      toastRef.current = undefined;
      setOpen(false);
      setChangelogToDelete(null);
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to delete changelog: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const openDeleteDialog = (changelogId: string, changelogTitle: string) => {
    setChangelogToDelete({ id: changelogId, title: changelogTitle });
    setOpen(true);
  };

  const handleDelete = () => {
    if (changelogToDelete) {
      deleteMutation.execute({ id: changelogToDelete.id });
    }
  };

  const handleClose = () => {
    setOpen(false);
    setChangelogToDelete(null);
  };

  return (
    <DeleteChangelogContext.Provider value={{ openDeleteDialog }}>
      {children}
      <Dialog onOpenChange={setOpen} open={open}>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle>Delete Changelog</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete the changelog &quot;
              {changelogToDelete?.title}&quot;? This action cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              data-testid="confirm-delete-button"
              disabled={deleteMutation.status === "executing"}
              onClick={handleDelete}
              variant="destructive"
            >
              {deleteMutation.status === "executing" ? "Deleting..." : "Delete"}
            </Button>
            <Button onClick={handleClose} variant="outline">
              Cancel
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </DeleteChangelogContext.Provider>
  );
}
