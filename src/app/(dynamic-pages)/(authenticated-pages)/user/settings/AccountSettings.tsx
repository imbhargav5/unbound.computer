'use client';
import { PageHeading } from '@/components/PageHeading';
import { UpdateAvatarAndNameBody } from '@/components/UpdateAvatarAndName';
import {
  updateUserProfileNameAndAvatar,
  uploadPublicUserAvatar,
} from '@/data/user/user';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import type { Table } from '@/types';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { ConfirmDeleteAccountDialog } from './ConfirmDeleteAccountDialog';

export function AccountSettings({
  userProfile,
  userEmail
}: {
  userProfile: Table<'user_profiles'>;
  userEmail: string | undefined;
}) {
  const router = useRouter();
  const { mutate, isLoading } = useSAToastMutation(
    async ({
      fullName,
      avatarUrl,
    }: {
      fullName: string;
      avatarUrl?: string;
    }) => {
      return await updateUserProfileNameAndAvatar({
        fullName,
        avatarUrl,
      });
    },
    {
      loadingMessage: 'Updating profile...',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update profile ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to update profile';
        }
      },
      successMessage: 'Profile updated!',
    },
  );
  // This loading state is for the new avatar image
  // being fetched from the server to the browser. At this point the
  // upload is complete, but the new image is not yet available to the browser.
  const [isNewAvatarImageLoading, setIsNewAvatarImageLoading] =
    useState<boolean>(false);

  const [avatarUrl, setAvatarUrl] = useState<string | undefined>(
    userProfile.avatar_url ?? undefined,
  );

  const { mutate: upload, isLoading: isUploading } = useSAToastMutation(
    async (file: File) => {
      const formData = new FormData();
      formData.append('file', file);
      return await uploadPublicUserAvatar(formData, file.name, {
        upsert: true,
      });
    },
    {
      loadingMessage: 'Uploading avatar...',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to upload avatar ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to upload avatar';
        }
      },
      successMessage: 'Avatar uploaded!',
      onSuccess: (response) => {
        if (response.status === 'success' && response.data) {
          router.refresh();
          setAvatarUrl(response.data);
          setIsNewAvatarImageLoading(true);
        }
      },
      onError: (error) => {
        console.log(String(error));
      },
    },
  );

  return (
    <div className="max-w-sm">
      <div className="space-y-16">
        <UpdateAvatarAndNameBody
          onSubmit={(fullName: string) => {
            mutate({
              fullName,
              avatarUrl,
            });
          }}
          onFileUpload={(file: File) => {
            upload(file);
          }}
          userId={userProfile.id}
          userEmail={userEmail}
          isNewAvatarImageLoading={isNewAvatarImageLoading}
          setIsNewAvatarImageLoading={setIsNewAvatarImageLoading}
          isUploading={isUploading}
          isLoading={isLoading ?? isUploading}
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
