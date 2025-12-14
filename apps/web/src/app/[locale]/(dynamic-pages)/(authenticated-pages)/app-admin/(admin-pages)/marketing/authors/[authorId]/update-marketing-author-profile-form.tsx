// src/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/authors/[authorId]/UpdateMarketingAuthorProfileForm.tsx
"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Camera } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import type React from "react";
import { useEffect, useRef, useState } from "react";
import { useForm } from "react-hook-form";
import slugify from "slugify";
import { toast } from "sonner";
import type { z } from "zod";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  updateAuthorProfileAction,
  uploadMarketingAuthorImageAction,
} from "@/data/admin/marketing-authors";
import { useRouter } from "@/i18n/navigation";
import type { DBTable } from "@/types";
import { getInitials } from "@/utils/generate-avatar";
import { updateMarketingAuthorProfileSchema } from "@/utils/zod-schemas/marketing-authors";
import { AuthorAvatarPickerDialog } from "../author-avatar-picker-dialog";

type FormData = z.infer<typeof updateMarketingAuthorProfileSchema>;

interface UpdateMarketingAuthorProfileFormProps {
  author: DBTable<"marketing_author_profiles">;
}

export const UpdateMarketingAuthorProfileForm: React.FC<
  UpdateMarketingAuthorProfileFormProps
> = ({ author }) => {
  const [avatarUrl, setAvatarUrl] = useState<string>(author.avatar_url);
  const [isAvatarPickerOpen, setIsAvatarPickerOpen] = useState(false);
  const toastRef = useRef<string | number | undefined>(undefined);
  const router = useRouter();

  const {
    register,
    handleSubmit,
    formState: { errors },
    setValue,
    watch,
  } = useForm<FormData>({
    resolver: zodResolver(updateMarketingAuthorProfileSchema),
    defaultValues: {
      id: author.id,
      slug: author.slug,
      display_name: author.display_name,
      bio: author.bio,
      avatar_url: author.avatar_url,
      website_url: author.website_url ?? undefined,
      twitter_handle: author.twitter_handle ?? undefined,
      facebook_handle: author.facebook_handle ?? undefined,
      linkedin_handle: author.linkedin_handle ?? undefined,
    },
  });

  const displayName = watch("display_name");

  useEffect(() => {
    if (displayName) {
      const slug = slugify(displayName, {
        lower: true,
        strict: true,
        replacement: "-",
      });
      setValue("slug", slug, { shouldValidate: true });
    }
  }, [displayName, setValue]);

  const updateProfileMutation = useAction(updateAuthorProfileAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Updating profile...", {
        description: "Please wait while we update the profile.",
      });
    },
    onSuccess: () => {
      toast.success("Profile updated!", { id: toastRef.current });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to update profile: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
  });

  const uploadAvatarMutation = useAction(uploadMarketingAuthorImageAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Uploading avatar...", {
        description: "Please wait while we upload your avatar.",
      });
    },
    onSuccess: ({ data }) => {
      if (!data) {
        throw new Error("No data returned from upload");
      }
      setAvatarUrl(data);
      setValue("avatar_url", data);
      toast.success("Avatar uploaded!", {
        description: "Your avatar has been successfully uploaded.",
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      toast.error(
        `Error uploading avatar: ${error.serverError || "Unknown error"}`,
        { id: toastRef.current }
      );
      toastRef.current = undefined;
    },
  });

  const handleAvatarSelect = (url: string) => {
    setAvatarUrl(url);
    setValue("avatar_url", url, { shouldValidate: true });
  };

  const handleAvatarUpload = (file: File) => {
    const formData = new FormData();
    formData.append("file", file);
    uploadAvatarMutation.execute({ formData });
  };

  const onSubmit = (data: FormData) => {
    updateProfileMutation.execute(data);
  };

  const initials = getInitials(displayName || author.display_name || "Author");

  return (
    <>
      <form className="space-y-6" onSubmit={handleSubmit(onSubmit)}>
        <div className="grid gap-6">
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="avatar-upload">
              Avatar <span className="text-destructive">*</span>
            </Label>
            <div className="sm:col-span-3">
              <button
                className="group relative cursor-pointer"
                onClick={() => setIsAvatarPickerOpen(true)}
                type="button"
              >
                <Avatar className="size-16 ring-1 ring-border">
                  <AvatarImage alt="Author avatar" src={avatarUrl} />
                  <AvatarFallback className="bg-muted text-base">
                    {initials}
                  </AvatarFallback>
                </Avatar>
                <div className="absolute inset-0 flex items-center justify-center rounded-full bg-black/50 opacity-0 transition-opacity group-hover:opacity-100">
                  <Camera className="size-4 text-white" />
                </div>
              </button>
              <p className="mt-2 text-muted-foreground text-xs">
                Click to change avatar
              </p>
            </div>
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="slug">
              Slug <span className="text-destructive">*</span>
            </Label>
            <Input className="sm:col-span-3" id="slug" {...register("slug")} />
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="display_name">
              Display Name <span className="text-destructive">*</span>
            </Label>
            <Input
              className="sm:col-span-3"
              id="display_name"
              {...register("display_name")}
            />
          </div>
          <div className="grid items-start gap-4 sm:grid-cols-4">
            <Label className="pt-2 sm:text-right" htmlFor="bio">
              Bio <span className="text-destructive">*</span>
            </Label>
            <Textarea
              className="min-h-[100px] sm:col-span-3"
              id="bio"
              {...register("bio")}
            />
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="website_url">
              Website URL{" "}
              <span className="text-muted-foreground text-sm">(optional)</span>
            </Label>
            <Input
              className="sm:col-span-3"
              id="website_url"
              {...register("website_url")}
            />
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="twitter_handle">
              Twitter Handle{" "}
              <span className="text-muted-foreground text-sm">(optional)</span>
            </Label>
            <Input
              className="sm:col-span-3"
              id="twitter_handle"
              {...register("twitter_handle")}
            />
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="facebook_handle">
              Facebook Handle{" "}
              <span className="text-muted-foreground text-sm">(optional)</span>
            </Label>
            <Input
              className="sm:col-span-3"
              id="facebook_handle"
              {...register("facebook_handle")}
            />
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="linkedin_handle">
              LinkedIn Handle{" "}
              <span className="text-muted-foreground text-sm">(optional)</span>
            </Label>
            <Input
              className="sm:col-span-3"
              id="linkedin_handle"
              {...register("linkedin_handle")}
            />
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="instagram_handle">
              Instagram Handle{" "}
              <span className="text-muted-foreground text-sm">(optional)</span>
            </Label>
            <Input
              className="sm:col-span-3"
              id="instagram_handle"
              {...register("instagram_handle")}
            />
          </div>
        </div>
        <div className="flex justify-end">
          <Button
            disabled={updateProfileMutation.status === "executing"}
            type="submit"
          >
            {updateProfileMutation.status === "executing"
              ? "Updating..."
              : "Update Profile"}
          </Button>
        </div>
      </form>

      <AuthorAvatarPickerDialog
        currentAvatarUrl={avatarUrl}
        displayName={displayName || author.display_name}
        isUploading={uploadAvatarMutation.status === "executing"}
        onAvatarSelect={handleAvatarSelect}
        onAvatarUpload={handleAvatarUpload}
        onOpenChange={setIsAvatarPickerOpen}
        open={isAvatarPickerOpen}
      />
    </>
  );
};
