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
import { sendLoginLinkAction } from '@/data/admin/user';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { Send } from 'lucide-react';
import { useState } from 'react';

export const ConfirmSendLoginLinkDialog = ({
  userEmail,
}: {
  userEmail: string;
}) => {
  const [open, setOpen] = useState(false);
  const { mutate: onConfirm, isLoading } = useSAToastMutation(
    async () => {
      return await sendLoginLinkAction(userEmail);
    },
    {
      loadingMessage: 'Sending login link...',
      successMessage: 'Login link sent!',
      errorMessage: 'Failed to send login link',
    },
  );
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant={'ghost'} aria-disabled={isLoading}>
          Send login link
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <div className="p-3 w-fit bg-gray-200/50 dark:bg-gray-700/40 mb-2 rounded-lg">
            <Send className=" w-6 h-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">Send Login Link</DialogTitle>
            <DialogDescription className="text-base mt-0">
              Are you sure you want to send a login link to the user?
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
            aria-disabled={isLoading}
            onClick={() => {
              onConfirm();
              setOpen(false);
            }}
          >
            Send Login Link
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
