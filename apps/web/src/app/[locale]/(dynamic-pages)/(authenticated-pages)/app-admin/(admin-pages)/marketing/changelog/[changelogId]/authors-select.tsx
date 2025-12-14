"use client";

import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { useRef } from "react";
import { toast } from "sonner";
import { Label } from "@/components/ui/label";
import { MultiSelect } from "@/components/ui/multi-select";
import { updateChangelogAuthorsAction } from "@/data/admin/marketing-changelog";
import type { DBTable } from "@/types";

type AuthorsSelectProps = {
  changelog: {
    id: string;
    marketing_changelog_author_relationship: { author_id: string }[];
  };
  authors: DBTable<"marketing_author_profiles">[];
};

export const AuthorsSelect: React.FC<AuthorsSelectProps> = ({
  changelog,
  authors,
}) => {
  const toastRef = useRef<string | number | undefined>(undefined);

  const selectedAuthorIds =
    changelog.marketing_changelog_author_relationship.map((a) => a.author_id);

  const updateAuthorsMutation = useAction(updateChangelogAuthorsAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Updating authors...", {
        description: "Please wait while we update the authors.",
      });
    },
    onSuccess: () => {
      toast.success("Authors updated successfully", { id: toastRef.current });
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to update authors: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const handleValueChange = (selectedValues: string[]) => {
    updateAuthorsMutation.execute({
      changelogId: changelog.id,
      authorIds: selectedValues,
    });
  };

  const options = authors.map((author) => ({
    value: author.id,
    label: author.display_name,
  }));

  return (
    <div className="space-y-2">
      <Label className="text-sm" htmlFor="authors">
        Authors
      </Label>

      <MultiSelect
        defaultValue={selectedAuthorIds}
        hideSelectAll
        maxCount={2}
        onValueChange={handleValueChange}
        options={options}
        placeholder="Select authors..."
      />
    </div>
  );
};
