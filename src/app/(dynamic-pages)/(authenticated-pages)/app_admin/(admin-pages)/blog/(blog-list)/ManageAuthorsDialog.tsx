"use client";
import { T } from "@/components/ui/Typography";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { adminDeleteAuthorProfileAction } from "@/data/admin/internal-blog";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import type { DBTable } from "@/types";
import { Trash, Users } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { AddAuthorProfileDialog } from "./AddAuthorProfileDialog";
import { EditAuthorProfileDialog } from "./EditAuthorProfileDialog";

type AuthorProfile = DBTable<"internal_blog_author_profiles">;

export const ManageAuthorsDialog = ({
  appAdmins,
  authorProfiles,
}: {
  appAdmins: Array<DBTable<"user_profiles">>;
  authorProfiles: Array<DBTable<"internal_blog_author_profiles">>;
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();

  const {
    mutate: deleteAuthorProfileMutation,
    isLoading: isDeletingAuthorProfile,
  } = useSAToastMutation(
    async (id: string) => {
      return await adminDeleteAuthorProfileAction(id);
    },
    {
      loadingMessage: "Deleting author profile...",
      successMessage: "Author profile deleted!",
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to delete author profile ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to delete author profile';
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
        <Button variant="outline" className="justify-start">
          <Users className="mr-2 size-4" />
          Manage author profiles
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <div className="p-3 w-fit bg-gray-200/50 dark:bg-gray-700/40 rounded-lg">
            <Users className="w-6 h-6" />
          </div>
          <div className="p-1 mb-4">
            <DialogTitle className="text-lg">
              Manage author profiles
            </DialogTitle>
            <DialogDescription className="text-base">
              View, edit, or delete author profiles.
            </DialogDescription>
          </div>
        </DialogHeader>
        <div className="space-y-6">
          <div className="space-y-2 mb-4">
            {authorProfiles.map((profile) => (
              <div
                className="flex space-x-1 items-center justify-between"
                key={profile.user_id}
              >
                <div className="flex gap-3 items-center">
                  <div className="h-10 w-10 rounded-full bg-gray-300/50 border dark:bg-gray-700/40 flex items-center justify-center">
                    <T.P className="font-semibold text-gray-800 dark:text-gray-400 uppercase">
                      {profile.display_name ? profile.display_name[0] : ""}
                    </T.P>
                  </div>

                  <T.P>{profile.display_name}</T.P>
                </div>

                <div className="flex items-center">
                  <EditAuthorProfileDialog
                    appAdmins={appAdmins}
                    profile={profile}
                  />
                  <Button
                    variant="ghost"
                    className="text-red-600 dark:text-red-400 hover:text-red-600  shadow-none hover:bg-red-100/50 dark:hover:bg-red-900/20"
                    onClick={() => {
                      deleteAuthorProfileMutation(profile.user_id);
                    }}
                  >
                    <Trash className="h-5 w-5" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </div>
        <DialogFooter>
          <Button
            variant="outline"
            className="w-full"
            onClick={() => {
              setIsOpen(false);
            }}
          >
            Cancel
          </Button>
          <AddAuthorProfileDialog
            appAdmins={appAdmins}
            authorProfiles={authorProfiles}
          />
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
