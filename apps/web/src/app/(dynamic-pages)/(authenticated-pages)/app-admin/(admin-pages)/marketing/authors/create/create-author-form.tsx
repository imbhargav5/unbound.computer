"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { Camera, Loader, Plus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import { useEffect, useRef, useState } from "react";
import { useForm } from "react-hook-form";
import slugify from "slugify";
import { toast } from "sonner";
import { z } from "zod";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  createAuthorProfileAction,
  uploadMarketingAuthorImageAction,
} from "@/data/admin/marketing-authors";
import { getInitials } from "@/utils/generate-avatar";
import { AuthorAvatarPickerDialog } from "../author-avatar-picker-dialog";

const createAuthorFormSchema = z.object({
  display_name: z.string().min(1, "Display name is required"),
  slug: z.string().min(1, "Slug is required"),
  bio: z.string().min(1, "Bio is required"),
  avatar_url: z.string().min(1, "Avatar is required"),
});

type FormData = z.infer<typeof createAuthorFormSchema>;

export function CreateAuthorForm() {
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);
  const [avatarUrl, setAvatarUrl] = useState<string>("");
  const [isAvatarPickerOpen, setIsAvatarPickerOpen] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
    setValue,
    watch,
  } = useForm<FormData>({
    resolver: zodResolver(createAuthorFormSchema),
    defaultValues: {
      display_name: "",
      slug: "",
      bio: "",
      avatar_url: "",
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

  const createMutation = useAction(createAuthorProfileAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Creating author profile...", {
        description: "Please wait while we create the profile.",
      });
    },
    onSuccess: ({ data }) => {
      toast.success("Author profile created!", {
        description: "Redirecting to edit page...",
        id: toastRef.current,
      });
      toastRef.current = undefined;
      if (data) {
        router.push(`/app-admin/marketing/authors/${data.id}`);
      }
    },
    onError: ({ error }) => {
      toast.error(
        `Failed to create profile: ${error.serverError || "Unknown error"}`,
        {
          description: "Please try again.",
          id: toastRef.current,
        }
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
      setValue("avatar_url", data, { shouldValidate: true });
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
    createMutation.execute(data);
  };

  const initials = getInitials(displayName || "Author");

  return (
    <>
      <div className="mb-6">
        <p className="text-muted-foreground text-sm">Create New</p>
        <h1 className="font-bold text-3xl">Author Profile</h1>
      </div>
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
                Click to choose an avatar
              </p>
              {errors.avatar_url ? (
                <p className="mt-1 text-destructive text-sm">
                  {errors.avatar_url.message}
                </p>
              ) : null}
            </div>
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="display_name">
              Display Name <span className="text-destructive">*</span>
            </Label>
            <div className="sm:col-span-3">
              <Input
                id="display_name"
                placeholder="Enter display name"
                {...register("display_name")}
              />
              {errors.display_name ? (
                <p className="mt-1 text-destructive text-sm">
                  {errors.display_name.message}
                </p>
              ) : null}
            </div>
          </div>
          <div className="grid items-center gap-4 sm:grid-cols-4">
            <Label className="sm:text-right" htmlFor="slug">
              Slug <span className="text-destructive">*</span>
            </Label>
            <div className="sm:col-span-3">
              <Input
                id="slug"
                placeholder="author-slug"
                {...register("slug")}
              />
              {errors.slug ? (
                <p className="mt-1 text-destructive text-sm">
                  {errors.slug.message}
                </p>
              ) : null}
            </div>
          </div>
          <div className="grid items-start gap-4 sm:grid-cols-4">
            <Label className="pt-2 sm:text-right" htmlFor="bio">
              Bio <span className="text-destructive">*</span>
            </Label>
            <div className="sm:col-span-3">
              <Textarea
                className="min-h-[100px]"
                id="bio"
                placeholder="Enter author bio..."
                {...register("bio")}
              />
              {errors.bio ? (
                <p className="mt-1 text-destructive text-sm">
                  {errors.bio.message}
                </p>
              ) : null}
            </div>
          </div>
        </div>
        <div className="flex justify-end">
          <Button
            disabled={createMutation.status === "executing"}
            type="submit"
          >
            {createMutation.status === "executing" ? (
              <>
                <Loader className="h-4 w-4 animate-spin" />
                Creating...
              </>
            ) : (
              <>
                <Plus className="h-4 w-4" />
                Create Author Profile
              </>
            )}
          </Button>
        </div>
      </form>

      <AuthorAvatarPickerDialog
        currentAvatarUrl={avatarUrl}
        displayName={displayName}
        isUploading={uploadAvatarMutation.status === "executing"}
        onAvatarSelect={handleAvatarSelect}
        onAvatarUpload={handleAvatarUpload}
        onOpenChange={setIsAvatarPickerOpen}
        open={isAvatarPickerOpen}
      />
    </>
  );
}
