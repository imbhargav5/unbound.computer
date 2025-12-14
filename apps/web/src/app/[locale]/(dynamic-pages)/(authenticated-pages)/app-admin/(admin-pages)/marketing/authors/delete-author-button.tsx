// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/authors/DeleteAuthorButton.tsx
"use client";

import { Trash } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useDeleteAuthor } from "./delete-author-provider";

type DeleteAuthorButtonProps = {
  authorId: string;
  authorName: string;
};

export function DeleteAuthorButton({
  authorId,
  authorName,
}: DeleteAuthorButtonProps) {
  const { openDeleteDialog } = useDeleteAuthor();

  return (
    <Button
      onClick={() => openDeleteDialog(authorId, authorName)}
      size="sm"
      variant="outline"
    >
      <Trash className="h-4 w-4" />
    </Button>
  );
}
