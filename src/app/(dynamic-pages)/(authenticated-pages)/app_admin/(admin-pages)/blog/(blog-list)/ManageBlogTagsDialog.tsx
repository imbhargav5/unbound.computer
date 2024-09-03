"use client";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { deleteBlogTag } from "@/data/admin/internal-blog";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import type { DBTable } from "@/types";
import { Tag, Trash } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { AddBlogTagDialog } from "./AddBlogTagDialog";
import { EditBlogTagDialog } from "./EditBlogTagDialog";

export const ManageBlogTagsDialog = ({
  blogTags,
}: {
  blogTags: Array<DBTable<"internal_blog_post_tags">>;
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();

  const { mutate: deleteBlogTagMutation, isLoading: isDeletingBlogTag } =
    useSAToastMutation(
      async (slug: number) => {
        return await deleteBlogTag(slug);
      },
      {
        loadingMessage: "Deleting blog tag...",
        successMessage: "Blog tag deleted!",
        errorMessage(error) {
          try {
            if (error instanceof Error) {
              return String(error.message);
            }
            return `Failed to delete blog tag ${String(error)}`;
          } catch (_err) {
            console.warn(_err);
            return 'Failed to delete blog tag';
          }
        },
        onSuccess: () => {
          router.refresh();
        },
      },
    );

  return (
    <Dialog open={isOpen} onOpenChange={(newIsOpen) => setIsOpen(newIsOpen)}>
      <DialogTrigger asChild>
        <Button variant="outline" className="text-start justify-start">
          <Tag className="mr-2 w-5 h-5" />
          Manage blog tags
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <div className="p-3 w-fit bg-gray-200/50 dark:bg-gray-700/40 rounded-lg">
            <Tag className="size-4" />
          </div>
          <div className="p-1 mb-4">
            <DialogTitle className="text-lg">Manage blog tags</DialogTitle>
            <DialogDescription className="text-base">
              View, edit, or delete blog tags.
            </DialogDescription>
          </div>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1">
            {blogTags.map((tag) => (
              <div
                className="flex space-x-1 items-center justify-between"
                key={tag.slug}
              >
                <p>{tag.name}</p>
                <div className="flex items-center gap-1">
                  <EditBlogTagDialog tag={tag} />
                  <Button
                    variant="ghost"
                    disabled={isDeletingBlogTag}
                    className="text-red-600 dark:text-red-400 hover:text-red-600  shadow-none hover:bg-red-100/50 dark:hover:bg-red-900/20"
                    onClick={() => {
                      deleteBlogTagMutation(tag.id);
                      setIsOpen(false);
                    }}
                  >
                    <Trash className="h-5 w-5" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
          <AddBlogTagDialog />
        </div>
      </DialogContent>
    </Dialog>
  );
};
