"use client";

import { useHookFormActionErrorMapper } from "@next-cool-action/adapter-react-hook-form/hooks";
import { Camera } from "lucide-react";
import { useAction, useOptimisticAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { useForm } from "react-hook-form";
import { toast } from "sonner";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  updateProfilePictureUrlAction,
  updateUserFullNameAction,
  uploadPublicUserAvatarAction,
} from "@/data/user/user";
import { zodResolver } from "@/lib/zod-resolver";
import type { DBTable } from "@/types";
import { getInitials } from "@/utils/generate-avatar";
import { getUserAvatarUrl } from "@/utils/helpers";
import { profileUpdateFormSchema } from "@/utils/zod-schemas/profile";
import { AvatarPickerDialog } from "./avatar-picker-dialog";
import { ConfirmDeleteAccountDialog } from "./confirm-delete-account-dialog";

export function AccountSettings({
  userProfile,
  userEmail,
}: {
  userProfile: DBTable<"user_profiles">;
  userEmail: string | undefined;
}) {
  const toastRef = useRef<string | number | undefined>(undefined);
  const [isAvatarPickerOpen, setIsAvatarPickerOpen] = useState(false);

  const [avatarUrl, setAvatarUrl] = useState<string | undefined>(
    userProfile.avatar_url ?? undefined
  );

  const [fullName, setFullName] = useState(userProfile.full_name ?? "");

  // Update full name action
  const {
    execute: updateUserName,
    status: updateNameStatus,
    result: updateNameResult,
  } = useOptimisticAction(updateUserFullNameAction, {
    currentState: userProfile.full_name ?? "",
    updateFn: (_, { fullName }) => fullName,
    onExecute: () => {
      toastRef.current = toast.loading("Updating name...");
    },
    onSuccess: () => {
      toast.success("Name updated!", {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      const errorMessage = error.serverError ?? "Failed to update name";
      toast.error(errorMessage, {
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
  });

  // Upload custom avatar action
  const { execute: uploadAvatar, status: uploadAvatarStatus } =
    useOptimisticAction(uploadPublicUserAvatarAction, {
      onExecute: () => {
        toastRef.current = toast.loading("Uploading avatar...");
      },
      onSuccess: ({ data }) => {
        setAvatarUrl(data);
        toast.success("Avatar uploaded!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to upload avatar";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      currentState: avatarUrl,
      updateFn: (_, { formData }) => {
        try {
          const file = formData.get("file");
          if (file instanceof File) {
            return URL.createObjectURL(file);
          }
        } catch (error) {
          console.error(error);
        }
        return avatarUrl;
      },
    });

  // Update avatar URL action (for DiceBear selection)
  const { execute: updateAvatarUrl, isPending: isUpdatingAvatarUrl } =
    useAction(updateProfilePictureUrlAction, {
      onExecute: () => {
        toastRef.current = toast.loading("Updating avatar...");
      },
      onSuccess: ({ data }) => {
        if (data) {
          setAvatarUrl(data);
        }
        toast.success("Avatar updated!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to update avatar";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    });

  const { hookFormValidationErrors } = useHookFormActionErrorMapper<
    typeof profileUpdateFormSchema
  >(updateNameResult.validationErrors, { joinBy: "\n" });

  const form = useForm({
    resolver: zodResolver(profileUpdateFormSchema),
    defaultValues: {
      fullName: userProfile.full_name ?? "",
    },
    errors: hookFormValidationErrors,
  });

  const handleAvatarSelect = (url: string) => {
    updateAvatarUrl({ profilePictureUrl: url });
  };

  const handleAvatarUpload = (file: File) => {
    const formData = new FormData();
    formData.append("file", file);
    uploadAvatar({
      formData,
      fileName: file.name,
      fileOptions: {
        upsert: true,
      },
    });
  };

  const handleSaveName = () => {
    if (fullName.trim()) {
      updateUserName({ fullName });
    }
  };

  const avatarUrlWithFallback = getUserAvatarUrl({
    profileAvatarUrl: avatarUrl ?? userProfile.avatar_url,
    email: userEmail,
  });

  const initials = getInitials(fullName || userProfile.full_name || "");

  return (
    <div className="max-w-lg">
      <div className="space-y-8">
        {/* Profile Photo Row */}
        <div className="flex items-start justify-between border-b pb-8">
          <div>
            <h3 className="font-medium text-sm">Profile Photo</h3>
            <p className="mt-0.5 text-muted-foreground text-sm">
              Click to choose a new avatar.
            </p>
          </div>
          <button
            className="group relative cursor-pointer"
            onClick={() => setIsAvatarPickerOpen(true)}
            type="button"
          >
            <Avatar className="size-16 ring-1 ring-border">
              <AvatarImage alt="Profile" src={avatarUrlWithFallback} />
              <AvatarFallback className="bg-muted text-base">
                {initials}
              </AvatarFallback>
            </Avatar>
            <div className="absolute inset-0 flex items-center justify-center rounded-full bg-black/50 opacity-0 transition-opacity group-hover:opacity-100">
              <Camera className="size-4 text-white" />
            </div>
          </button>
        </div>

        {/* Full Name Row */}
        <div className="flex items-start justify-between gap-8 border-b pb-8">
          <div className="shrink-0">
            <h3 className="font-medium text-sm">Full Name</h3>
            <p className="mt-0.5 text-muted-foreground text-sm">
              Your display name.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Input
              className="h-9 w-56"
              onChange={(e) => setFullName(e.target.value)}
              placeholder="Enter your name"
              value={fullName}
            />
            <Button
              disabled={updateNameStatus === "executing" || !fullName.trim()}
              onClick={handleSaveName}
              size="sm"
              variant="outline"
            >
              {updateNameStatus === "executing" ? "Saving..." : "Save"}
            </Button>
          </div>
        </div>

        {/* Delete Account Row */}
        <div className="flex items-start justify-between">
          <div>
            <h3 className="font-medium text-destructive text-sm">
              Delete Account
            </h3>
            <p className="mt-0.5 text-muted-foreground text-sm">
              Permanently delete your account and all data.
            </p>
          </div>
          <ConfirmDeleteAccountDialog />
        </div>
      </div>

      {/* Avatar Picker Dialog */}
      <AvatarPickerDialog
        currentAvatarUrl={avatarUrlWithFallback}
        fullName={fullName || userProfile.full_name || ""}
        isUploading={uploadAvatarStatus === "executing" || isUpdatingAvatarUrl}
        onAvatarSelect={handleAvatarSelect}
        onAvatarUpload={handleAvatarUpload}
        onOpenChange={setIsAvatarPickerOpen}
        open={isAvatarPickerOpen}
      />
    </div>
  );
}
