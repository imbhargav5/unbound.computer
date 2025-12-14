// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/tags/DeleteTagButton.tsx
"use client";

import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useDeleteTag } from "./delete-tag-provider";

type DeleteTagButtonProps = {
  tagId: string;
  tagName: string;
};

export function DeleteTagButton({ tagId, tagName }: DeleteTagButtonProps) {
  const { openDeleteDialog } = useDeleteTag();

  return (
    <Button
      onClick={() => openDeleteDialog(tagId, tagName)}
      size="sm"
      variant="outline"
    >
      <Trash2 className="h-4 w-4" />
    </Button>
  );
}
