// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/authors/DeleteAuthorProvider.tsx
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
import { deleteAuthorProfileAction } from "@/data/admin/marketing-authors";

type AuthorToDelete = {
  id: string;
  name: string;
};

type DeleteAuthorContextValue = {
  openDeleteDialog: (authorId: string, authorName: string) => void;
};

const DeleteAuthorContext = createContext<DeleteAuthorContextValue | undefined>(
  undefined
);

export function useDeleteAuthor() {
  const context = useContext(DeleteAuthorContext);
  if (!context) {
    throw new Error("useDeleteAuthor must be used within DeleteAuthorProvider");
  }
  return context;
}

type DeleteAuthorProviderProps = {
  children: React.ReactNode;
};

export function DeleteAuthorProvider({ children }: DeleteAuthorProviderProps) {
  const [authorToDelete, setAuthorToDelete] = useState<AuthorToDelete | null>(
    null
  );
  const [open, setOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const deleteMutation = useAction(deleteAuthorProfileAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Deleting profile...", {
        description: "Please wait while we delete the profile.",
      });
    },
    onSuccess: () => {
      toast.success("Profile deleted!", { id: toastRef.current });
      toastRef.current = undefined;
      setOpen(false);
      setAuthorToDelete(null);
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to delete profile: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const openDeleteDialog = (authorId: string, authorName: string) => {
    setAuthorToDelete({ id: authorId, name: authorName });
    setOpen(true);
  };

  const handleDelete = () => {
    if (authorToDelete) {
      deleteMutation.execute({ id: authorToDelete.id });
    }
  };

  const handleClose = () => {
    setOpen(false);
    setAuthorToDelete(null);
  };

  return (
    <DeleteAuthorContext.Provider value={{ openDeleteDialog }}>
      {children}
      <Dialog onOpenChange={setOpen} open={open}>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle>Delete Author Profile</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete the profile for{" "}
              {authorToDelete?.name}? This action cannot be undone.
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
    </DeleteAuthorContext.Provider>
  );
}
