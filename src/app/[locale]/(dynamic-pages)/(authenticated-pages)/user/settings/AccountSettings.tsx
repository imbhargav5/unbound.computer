"use client";
import { PageHeading } from "@/components/PageHeading";
import { UpdateAvatarAndNameBody } from "@/components/UpdateAvatarAndName";
import {
  updateUserProfileNameAndAvatarAction,
  uploadPublicUserAvatarAction,
} from "@/data/user/user";
import type { DBTable } from "@/types";
import { useAction } from "next-safe-action/hooks";
import { useRouter } from "next/navigation";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { ConfirmDeleteAccountDialog } from "./ConfirmDeleteAccountDialog";

export function AccountSettings({
  userProfile,
  userEmail,
}: {
  userProfile: DBTable<"user_profiles">;
  userEmail: string | undefined;
}) {
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: updateUserProfile, isPending: isUpdatingProfile } =
    useAction(updateUserProfileNameAndAvatarAction, {
      onExecute: () => {
        toastRef.current = toast.loading("Updating profile...");
      },
      onSuccess: () => {
        toast.success("Profile updated!", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to update profile";
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    });

  const [isNewAvatarImageLoading, setIsNewAvatarImageLoading] =
    useState<boolean>(false);
  const [avatarUrl, setAvatarUrl] = useState<string | undefined>(
    userProfile.avatar_url ?? undefined,
  );

  const { execute: uploadAvatar, isPending: isUploadingAvatar } = useAction(
    uploadPublicUserAvatarAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Uploading avatar...");
      },
      onSuccess: ({ data }) => {
        router.refresh();
        setIsNewAvatarImageLoading(true);
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
    },
  );

  return (
    <div className="max-w-sm">
      <div className="space-y-16">
        <UpdateAvatarAndNameBody
          onSubmit={(fullName: string) => {
            updateUserProfile({ fullName, avatarUrl });
          }}
          onFileUpload={(file: File) => {
            const formData = new FormData();
            formData.append("file", file);
            uploadAvatar({
              formData,
              fileName: file.name,
              fileOptions: { upsert: true },
            });
          }}
          userId={userProfile.id}
          userEmail={userEmail}
          isNewAvatarImageLoading={isNewAvatarImageLoading}
          setIsNewAvatarImageLoading={setIsNewAvatarImageLoading}
          isUploading={isUploadingAvatar}
          isLoading={isUpdatingProfile || isUploadingAvatar}
          profileAvatarUrl={avatarUrl ?? undefined}
          profileFullname={userProfile.full_name ?? undefined}
        />
        <div className="space-y-2">
          <PageHeading
            title="Danger zone"
            titleClassName="text-xl"
            subTitleClassName="text-base -mt-1"
            subTitle="Delete your account. This action is irreversible. All your data will be lost."
          />
          <ConfirmDeleteAccountDialog />
        </div>
      </div>
    </div>
  );
}
