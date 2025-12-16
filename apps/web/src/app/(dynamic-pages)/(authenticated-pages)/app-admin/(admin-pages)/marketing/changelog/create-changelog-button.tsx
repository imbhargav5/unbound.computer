"use client";

import { Plus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { createChangelogAction } from "@/data/admin/marketing-changelog";

export const CreateChangelogButton: React.FC = () => {
  const router = useRouter();

  const createChangelogMutation = useAction(createChangelogAction, {
    onError: ({ error }) => {
      toast.error(
        `Failed to create changelog: ${error.serverError || "Unknown error"}`,
        {
          description: "Please try again.",
        }
      );
    },
  });

  const handleCreateChangelog = () => {
    createChangelogMutation.execute({
      title: "New Changelog",
      stringified_json_content: JSON.stringify({}),
      status: "draft",
    });
  };

  return (
    <Button
      disabled={createChangelogMutation.status === "executing"}
      onClick={handleCreateChangelog}
    >
      <Plus className="mr-2 h-4 w-4" />
      {createChangelogMutation.status === "executing"
        ? "Creating..."
        : "Create Changelog"}
    </Button>
  );
};
