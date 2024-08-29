'use client';

import { T } from '@/components/ui/Typography';
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
import { Input } from '@/components/ui/input';
import { requestAccountDeletion } from '@/data/user/user';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { Trash } from 'lucide-react';
import { useState } from 'react';
import { ConfirmDeletionViaEmailDialog } from './ConfirmDeletionViaEmailDialog';

export const ConfirmDeleteAccountDialog = () => {
  const [open, setOpen] = useState(false);
  const [isSuccessDialogOpen, setIsSuccessDialogOpen] = useState(false);
  const [confirmText, setConfirmText] = useState('');
  const isDisabled = confirmText !== 'delete';
  const {
    mutate: mutateRequestAccountDeletion,
    isLoading: isRequestingAccountDeletion,
  } = useSAToastMutation(
    async () => {
      return requestAccountDeletion();
    },
    {
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed! ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed! ';
        }
      },
      loadingMessage: 'Creating deletion request...',
      successMessage:
        'Account deletion request created. Please check your email.',
      onSuccess: () => {
        setIsSuccessDialogOpen(true);
      },
    },
  );

  return (
    <>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogTrigger asChild>
          <Button className="w-full" variant="destructive">
            <Trash className="mr-2 h-5 w-5" /> Delete Account
          </Button>
        </DialogTrigger>
        <DialogContent className="sm:max-w-[425px]">
          <DialogHeader>
            <DialogTitle>Delete Account</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete your account? This action is
              irreversible. All your data will be lost.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Input
              value={confirmText}
              onChange={(e) => setConfirmText(e.target.value)}
              className="mt-4"
            />
            <T.Subtle className="pl-2">
              Type &quot;delete&quot; into the input to confirm.
            </T.Subtle>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button
              disabled={isDisabled ?? isRequestingAccountDeletion}
              variant="destructive"
              onClick={() => {
                mutateRequestAccountDeletion();
                setOpen(false);
              }}
            >
              {isRequestingAccountDeletion ? 'Deleting...' : 'Delete'} Account
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <ConfirmDeletionViaEmailDialog
        open={isSuccessDialogOpen}
        setOpen={setIsSuccessDialogOpen}
      />
    </>
  );
};
