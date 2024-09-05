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
import { Textarea } from "@/components/ui/textarea";
import { adminCreateAuthorProfileAction } from "@/data/admin/internal-blog";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import type { DBTable } from "@/types";
import { marketingAuthorProfileFormSchema } from "@/utils/zod-schemas/internalBlog";
import { zodResolver } from "@hookform/resolvers/zod";
import { UserPlus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Controller, useForm } from "react-hook-form";
import slugify from 'slugify';
import { toast } from "sonner";
import type { z } from "zod";

type AuthorProfileFormType = z.infer<typeof marketingAuthorProfileFormSchema>;

export const AddAuthorProfileDialog = ({
  appAdmins,
  authorProfiles,
}: {
  appAdmins: Array<DBTable<"user_profiles">>;
  authorProfiles: Array<DBTable<"marketing_author_profiles">>;
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const router = useRouter();
  const { control, handleSubmit, formState, reset, watch, setValue } =
    useForm<AuthorProfileFormType>({
      resolver: zodResolver(marketingAuthorProfileFormSchema),
    });

  const {
    mutate: createAuthorProfileMutation,
    isLoading: isCreatingAuthorProfile,
  } = useSAToastMutation(
    async (payload: AuthorProfileFormType) => {
      return adminCreateAuthorProfileAction(payload);
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

  const displayName = watch("display_name");

  useEffect(() => {
    if (typeof displayName === 'string') {
      const slug = slugify(displayName, {
        lower: true,
        strict: true,
        replacement: '-',
      });
      setValue('slug', slug);
    }
  }, [displayName, setValue]);

  const onSubmit = (data: AuthorProfileFormType) => {
    void createAuthorProfileMutation(data);
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
              <Label>Slug</Label>
              <Controller
                control={control}
                name="slug"
                render={({ field }) => (
                  <Input disabled {...field} placeholder="Slug" />
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
