// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/changelog/DeleteChangelogButton.tsx
"use client";

import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useDeleteChangelog } from "./delete-changelog-provider";

type DeleteChangelogButtonProps = {
  changelogId: string;
  changelogTitle: string;
};

export function DeleteChangelogButton({
  changelogId,
  changelogTitle,
}: DeleteChangelogButtonProps) {
  const { openDeleteDialog } = useDeleteChangelog();

  return (
    <Button
      data-testid="delete-changelog-dialog-trigger"
      onClick={() => openDeleteDialog(changelogId, changelogTitle)}
      size="sm"
      variant="outline"
    >
      <Trash2 className="h-4 w-4" />
    </Button>
  );
}
