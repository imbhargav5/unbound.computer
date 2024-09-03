"use client";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { createAuthorProfile } from "@/data/admin/internal-blog";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import type { DBTable } from "@/types";
import { authorProfileSchema } from "@/utils/zod-schemas/internalBlog";
import { zodResolver } from "@hookform/resolvers/zod";
import { UserPlus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Controller, useForm } from "react-hook-form";
import { toast } from "sonner";
import type { z } from "zod";

type AuthorProfileFormType = z.infer<typeof authorProfileSchema>;
export type CreateAuthorPayload = Omit<
  DBTable<"internal_blog_author_profiles">,
  "created_at" | "updated_at"
>;
export const AddAuthorProfileDialog = ({
  appAdmins,
  authorProfiles,
}: {
  appAdmins: Array<DBTable<"user_profiles">>;
  authorProfiles: Array<DBTable<"internal_blog_author_profiles">>;
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();
  const { control, handleSubmit, formState, reset, setValue } =
    useForm<AuthorProfileFormType>({
      resolver: zodResolver(authorProfileSchema),
    });

  const {
    mutate: createAuthorProfileMutation,
    isLoading: isCreatingAuthorProfile,
  } = useSAToastMutation(
    async (payload: CreateAuthorPayload) => {
      return createAuthorProfile(payload);
    },
    {
      onSuccess: () => {
        router.refresh();
        toast.success("Successfully created author profile");
        setIsOpen(false);
        reset();
      },
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to create author profile ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to create author profile';
        }
      },
    },
  );

  const { isValid, isLoading } = formState;

  const onSubmit = (data: AuthorProfileFormType) => {
    void createAuthorProfileMutation({
      user_id: data.user_id,
      display_name: data.display_name,
      bio: data.bio,
      avatar_url: data.avatar_url,
      website_url: data.website_url ?? null,
      twitter_handle: data.twitter_handle ?? null,
      facebook_handle: data.facebook_handle ?? null,
      linkedin_handle: data.linkedin_handle ?? null,
      instagram_handle: data.instagram_handle ?? null,
    });
  };

  return (
    <Dialog open={isOpen} onOpenChange={(newIsOpen) => setIsOpen(newIsOpen)}>
      <DialogTrigger asChild>
        <Button variant="default" className="w-full">
          Add new author profile
        </Button>
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <div className="p-3 w-fit bg-gray-200/50 dark:bg-gray-700/40 rounded-lg">
            <UserPlus className="w-6 h-6" />
          </div>
          <div className="p-1 mb-4">
            <DialogTitle className="text-lg">Add Author Profile</DialogTitle>
            <DialogDescription className="text-base">
              Fill in the details for the new author profile.
            </DialogDescription>
          </div>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 ">
          <div className="fields space-y-4 max-h-96 px-1 overflow-auto">
            <div className="space-y-2">
              <Label>User ID</Label>
              <Controller
                control={control}
                name="user_id"
                render={({ field }) => (
                  <Select value={field.value} onValueChange={field.onChange}>
                    <SelectTrigger>
                      <SelectValue placeholder="Select user" />
                    </SelectTrigger>
                    <SelectContent>
                      {appAdmins.map((admin) => {
                        const disabled = authorProfiles.some(
                          (profile) => profile.user_id === admin.id,
                        );
                        return (
                          <SelectItem key={admin.id} value={admin.id}>
                            {admin.full_name || `User ${admin.id}`}
                          </SelectItem>
                        );
                      })}
                    </SelectContent>
                  </Select>
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Display Name</Label>
              <Controller
                control={control}
                name="display_name"
                render={({ field }) => (
                  <Input {...field} placeholder="Display Name" />
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Bio</Label>
              <Controller
                control={control}
                name="bio"
                render={({ field }) => (
                  <Textarea {...field} placeholder="Bio" />
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Avatar URL</Label>
              <Controller
                control={control}
                name="avatar_url"
                render={({ field }) => (
                  <Input {...field} placeholder="Avatar URL" />
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Website URL</Label>
              <Controller
                control={control}
                name="website_url"
                render={({ field }) => (
                  <Input {...field} placeholder="Website URL" />
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Twitter Handle</Label>
              <Controller
                control={control}
                name="twitter_handle"
                render={({ field }) => (
                  <Input {...field} placeholder="Twitter Handle" />
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Facebook Handle</Label>
              <Controller
                control={control}
                name="facebook_handle"
                render={({ field }) => (
                  <Input {...field} placeholder="Facebook Handle" />
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>LinkedIn Handle</Label>
              <Controller
                control={control}
                name="linkedin_handle"
                render={({ field }) => (
                  <Input {...field} placeholder="LinkedIn Handle" />
                )}
              />
            </div>
            <div className="space-y-1">
              <Label>Instagram Handle</Label>
              <Controller
                control={control}
                name="instagram_handle"
                render={({ field }) => (
                  <Input {...field} placeholder="Instagram Handle" />
                )}
              />
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
            <Button
              disabled={!isValid || isCreatingAuthorProfile}
              type="submit"
              className="w-full"
            >
              {isLoading || isCreatingAuthorProfile
                ? "Submitting..."
                : "Submit Profile"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
