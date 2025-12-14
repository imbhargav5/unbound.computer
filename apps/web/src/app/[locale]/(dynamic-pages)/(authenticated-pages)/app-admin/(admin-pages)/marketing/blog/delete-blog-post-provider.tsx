// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/DeleteBlogPostProvider.tsx
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
import { deleteBlogPostAction } from "@/data/admin/marketing-blog";

type BlogPostToDelete = {
  id: string;
  title: string;
};

type DeleteBlogPostContextValue = {
  openDeleteDialog: (postId: string, postTitle: string) => void;
};

const DeleteBlogPostContext = createContext<
  DeleteBlogPostContextValue | undefined
>(undefined);

export function useDeleteBlogPost() {
  const context = useContext(DeleteBlogPostContext);
  if (!context) {
    throw new Error(
      "useDeleteBlogPost must be used within DeleteBlogPostProvider"
    );
  }
  return context;
}

type DeleteBlogPostProviderProps = {
  children: React.ReactNode;
};

export function DeleteBlogPostProvider({
  children,
}: DeleteBlogPostProviderProps) {
  const [postToDelete, setPostToDelete] = useState<BlogPostToDelete | null>(
    null
  );
  const [open, setOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);

  const deleteMutation = useAction(deleteBlogPostAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Deleting blog post...", {
        description: "Please wait while we delete the post.",
      });
    },
    onSuccess: () => {
      toast.success("Blog post deleted successfully", { id: toastRef.current });
      toastRef.current = undefined;
      setOpen(false);
      setPostToDelete(null);
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to delete blog post: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const openDeleteDialog = (postId: string, postTitle: string) => {
    setPostToDelete({ id: postId, title: postTitle });
    setOpen(true);
  };

  const handleDelete = () => {
    if (postToDelete) {
      deleteMutation.execute({ id: postToDelete.id });
    }
  };

  const handleClose = () => {
    setOpen(false);
    setPostToDelete(null);
  };

  return (
    <DeleteBlogPostContext.Provider value={{ openDeleteDialog }}>
      {children}
      <Dialog onOpenChange={setOpen} open={open}>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle>Delete Blog Post</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete the blog post &quot;
              {postToDelete?.title}&quot;? This action cannot be undone.
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
    </DeleteBlogPostContext.Provider>
  );
}
