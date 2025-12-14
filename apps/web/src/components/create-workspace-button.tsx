"use client";

import { PlusIcon } from "@radix-ui/react-icons";
import { Button } from "@/components/ui/button";
import { useCreateWorkspaceDialog } from "@/hooks/use-create-workspace-dialog";

export function CreateWorkspaceButton({ onClick }: { onClick?: () => void }) {
  const { openDialog } = useCreateWorkspaceDialog();

  return (
    <Button
      className="w-full"
      onClick={() => {
        onClick?.();
        openDialog();
      }}
      size="sm"
    >
      <PlusIcon className="mr-2 h-4 w-4" />
      Create Team Workspace
    </Button>
  );
}
