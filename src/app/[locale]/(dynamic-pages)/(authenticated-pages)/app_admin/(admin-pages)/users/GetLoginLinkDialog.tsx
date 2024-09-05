'use client';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { appAdminGetUserImpersonationUrl } from '@/data/admin/user';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { Link } from 'lucide-react';
import { useState } from 'react';

export const GetLoginLinkDialog = ({ userId }: { userId: string }) => {
  const [open, setOpen] = useState(false);
  const { mutate: onConfirm, isLoading } = useSAToastMutation(
    async () => {
      return await appAdminGetUserImpersonationUrl(userId);
    },
    {
      onSuccess: (payload) => {
        navigator.clipboard.writeText((payload.data).toString());
      },
      loadingMessage: 'Generating login link...',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to generate login link ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to generate login link';
        }
      },
    },
  );
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="ghost" aria-disabled={isLoading}>
          Get login link
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <div className="p-3 w-fit bg-gray-200/50 dark:bg-gray-700/40 mb-2 rounded-lg">
            <Link className=" w-6 h-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">Get Login Link</DialogTitle>
            <DialogDescription className="text-base mt-0">
              Are you sure you want to generate a login link for the user?
            </DialogDescription>
          </div>
        </DialogHeader>
        <DialogFooter className="mt-2">
          <Button
            type="button"
            variant="outline"
            className="w-full"
            aria-disabled={isLoading}
            onClick={() => {
              setOpen(false);
            }}
          >
            Cancel
          </Button>
          <Button
            type="button"
            variant="default"
            className="w-full"
            onClick={() => {
              onConfirm();
              setOpen(false);
            }}
            aria-disabled={isLoading}
          >
            Get Login Link
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
