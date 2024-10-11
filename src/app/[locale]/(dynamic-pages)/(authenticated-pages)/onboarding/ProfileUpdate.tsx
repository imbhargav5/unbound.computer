'use client';
import { Button } from '@/components/ui/button';
import {
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  updateUserProfileNameAndAvatarAction,
  uploadPublicUserAvatarAction,
} from '@/data/user/user';
import type { DBTable } from '@/types';
import { getUserAvatarUrl } from '@/utils/helpers';
import { useAction } from 'next-safe-action/hooks';
import Image from 'next/image';
import { useRef, useState } from 'react';
import { toast } from 'sonner';

type ProfileUpdateProps = {
  userProfile: DBTable<'user_profiles'>;
  onSuccess: () => void;
  userEmail: string | undefined;
};

export function ProfileUpdate({
  userProfile,
  onSuccess,
  userEmail,
}: ProfileUpdateProps) {
  const [fullName, setFullName] = useState(userProfile.full_name ?? '');
  const [avatarUrl, setAvatarUrl] = useState(
    userProfile.avatar_url ?? undefined,
  );
  const toastRef = useRef<string | number | undefined>(undefined);

  const avatarUrlWithFallback = getUserAvatarUrl({
    profileAvatarUrl: avatarUrl ?? userProfile.avatar_url,
    email: userEmail,
  });

  const updateProfileMutation = useAction(
    updateUserProfileNameAndAvatarAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading('Updating profile...', {
          description: 'Please wait while we update your profile.',
        });
      },
      onSuccess: () => {
        toast.success('Profile updated!', { id: toastRef.current });
        onSuccess();
      },
      onError: () => {
        toast.error('Failed to update profile', { id: toastRef.current });
      },
    },
  );

  const uploadAvatarMutation = useAction(uploadPublicUserAvatarAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Uploading avatar...', {
        description: 'Please wait while we upload your avatar.',
      });
    },
    onSuccess: (response) => {
      setAvatarUrl(response.data);
      toast.success('Avatar uploaded!', {
        description: 'Your avatar has been successfully uploaded.',
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
    onError: () => {
      toast.error('Error uploading avatar', { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const handleFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file) {
      const formData = new FormData();
      formData.append('file', file);
      uploadAvatarMutation.execute({
        formData,
        fileName: file.name,
        fileOptions: {
          upsert: true,
        },
      });
    }
  };

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        updateProfileMutation.execute({
          fullName,
          avatarUrl,
          isOnboardingFlow: true,
        });
      }}
    >
      <CardHeader>
        <CardTitle>Create Your Profile</CardTitle>
        <CardDescription>
          Let&apos;s set up your personal details.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <Label htmlFor="avatar">Avatar</Label>
          <div className="flex items-center space-x-4">
            <Image
              width={48}
              height={48}
              className="rounded-full"
              src={avatarUrlWithFallback}
              alt="User avatar"
            />
            <Label htmlFor="avatar-upload" className="cursor-pointer">
              <Input
                id="avatar-upload"
                type="file"
                className="hidden"
                onChange={handleFileChange}
                accept="image/*"
                disabled={uploadAvatarMutation.isPending}
              />
              <Button type="button" variant="outline" size="sm">
                {uploadAvatarMutation.isPending
                  ? 'Uploading...'
                  : 'Change Avatar'}
              </Button>
            </Label>
          </div>
        </div>
        <div className="space-y-2">
          <Label htmlFor="full-name">Full Name</Label>
          <Input
            id="full-name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            placeholder="Your full name"
            disabled={updateProfileMutation.isPending}
          />
        </div>
      </CardContent>
      <CardFooter>
        <Button
          type="submit"
          className="w-full"
          disabled={
            updateProfileMutation.isPending || uploadAvatarMutation.isPending
          }
        >
          {updateProfileMutation.isPending ? 'Saving...' : 'Save Profile'}
        </Button>
      </CardFooter>
    </form>
  );
}
