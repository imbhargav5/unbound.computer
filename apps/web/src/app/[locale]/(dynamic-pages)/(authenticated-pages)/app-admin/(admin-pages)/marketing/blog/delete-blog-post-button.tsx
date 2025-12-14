// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/DeleteBlogPostButton.tsx
"use client";

import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useDeleteBlogPost } from "./delete-blog-post-provider";

type DeleteBlogPostButtonProps = {
  postId: string;
  postTitle: string;
};

export function DeleteBlogPostButton({
  postId,
  postTitle,
}: DeleteBlogPostButtonProps) {
  const { openDeleteDialog } = useDeleteBlogPost();

  return (
    <Button
      data-testid="delete-blog-post-dialog-trigger"
      onClick={() => openDeleteDialog(postId, postTitle)}
      size="sm"
      variant="outline"
    >
      <Trash2 className="h-4 w-4" />
    </Button>
  );
}
