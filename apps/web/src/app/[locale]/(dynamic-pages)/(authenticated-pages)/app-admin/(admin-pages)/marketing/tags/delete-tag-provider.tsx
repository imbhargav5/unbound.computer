// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/tags/DeleteTagProvider.tsx
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
import { deleteMarketingTagAction } from "@/data/admin/marketing-tags";

type TagToDelete = {
  id: string;
  name: string;
};

type DeleteTagContextValue = {
  openDeleteDialog: (tagId: string, tagName: string) => void;
};

const DeleteTagContext = createContext<DeleteTagContextValue | undefined>(
  undefined
);

export function useDeleteTag() {
  const context = useContext(DeleteTagContext);
  if (!context) {
    throw new Error("useDeleteTag must be used within DeleteTagProvider");
  }
  return context;
}

type DeleteTagProviderProps = {
  children: React.ReactNode;
};

export function DeleteTagProvider({ children }: DeleteTagProviderProps) {
  const [tagToDelete, setTagToDelete] = useState<TagToDelete | null>(null);
  const [open, setOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const deleteMutation = useAction(deleteMarketingTagAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Deleting tag...", {
        description: "Please wait while we delete the tag.",
      });
    },
    onSuccess: () => {
      toast.success("Tag deleted successfully", { id: toastRef.current });
      toastRef.current = undefined;
      setOpen(false);
      setTagToDelete(null);
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to delete tag: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const openDeleteDialog = (tagId: string, tagName: string) => {
    setTagToDelete({ id: tagId, name: tagName });
    setOpen(true);
  };

  const handleDelete = () => {
    if (tagToDelete) {
      deleteMutation.execute({ id: tagToDelete.id });
    }
  };

  const handleClose = () => {
    setOpen(false);
    setTagToDelete(null);
  };

  return (
    <DeleteTagContext.Provider value={{ openDeleteDialog }}>
      {children}
      <Dialog onOpenChange={setOpen} open={open}>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle>Delete Tag</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete the tag &quot;
              {tagToDelete?.name}?&quot; This action cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
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
    </DeleteTagContext.Provider>
  );
}
