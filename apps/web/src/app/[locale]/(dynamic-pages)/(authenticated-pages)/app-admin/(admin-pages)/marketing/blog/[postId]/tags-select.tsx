// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/[postId]/TagsSelect.tsx
"use client";

import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { useRef } from "react";
import { toast } from "sonner";
import { Label } from "@/components/ui/label";
import { MultiSelect } from "@/components/ui/multi-select";
import { updateBlogPostTagsAction } from "@/data/admin/marketing-blog";
import type { DBTable } from "@/types";

type TagsSelectProps = {
  post: {
    id: string;
    marketing_blog_post_tags_relationship?: { tag_id: string }[];
  };
  tags: DBTable<"marketing_tags">[];
};

export const TagsSelect: React.FC<TagsSelectProps> = ({ post, tags }) => {
  const toastRef = useRef<string | number | undefined>(undefined);

  const selectedTagIds =
    post.marketing_blog_post_tags_relationship?.map((t) => t.tag_id) ?? [];

  const updateTagsMutation = useAction(updateBlogPostTagsAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Updating tags...", {
        description: "Please wait while we update the tags.",
      });
    },
    onSuccess: () => {
      toast.success("Tags updated successfully", { id: toastRef.current });
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to update tags: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
    },
    onSettled: () => {
      toastRef.current = undefined;
    },
  });

  const handleValueChange = (selectedValues: string[]) => {
    updateTagsMutation.execute({ postId: post.id, tagIds: selectedValues });
  };

  const options = tags.map((tag) => ({ value: tag.id, label: tag.name }));

  return (
    <div className="space-y-2">
      <Label className="text-sm" htmlFor="tags">
        Tags
      </Label>

      <MultiSelect
        defaultValue={selectedTagIds}
        hideSelectAll
        maxCount={2}
        onValueChange={handleValueChange}
        options={options}
        placeholder="Select tags..."
      />
    </div>
  );
};
