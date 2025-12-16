// @/app/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/[postId]/AuthorsSelect.tsx
"use client";

import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { useRef } from "react";
import { toast } from "sonner";
import { Label } from "@/components/ui/label";
import { MultiSelect } from "@/components/ui/multi-select";
import { updateBlogPostAuthorsAction } from "@/data/admin/marketing-blog";
import type { DBTable } from "@/types";

type AuthorsSelectProps = {
  post: {
    id: string;
    marketing_blog_author_posts?: { author_id: string }[];
  };
  authors: DBTable<"marketing_author_profiles">[];
};

export const AuthorsSelect: React.FC<AuthorsSelectProps> = ({
  post,
  authors,
}) => {
  const toastRef = useRef<string | number | undefined>(undefined);

  const selectedAuthorIds =
    post.marketing_blog_author_posts?.map((a) => a.author_id) ?? [];

  const updateAuthorsMutation = useAction(updateBlogPostAuthorsAction, {
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
      postId: post.id,
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
