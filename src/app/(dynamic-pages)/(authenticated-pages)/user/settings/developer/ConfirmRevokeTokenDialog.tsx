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
import { revokeUnkeyToken } from '@/data/user/unkey';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { useState } from 'react';

type Props = {
  keyId: string;
};

export const ConfirmRevokeTokenDialog = ({ keyId }: Props) => {
  const [open, setOpen] = useState(false);
  const { mutate, isLoading } = useSAToastMutation(async (keyId: string) => {
    return await revokeUnkeyToken(keyId);
  }, {
    onSettled: () => {
      setOpen(false);
    },
    loadingMessage: 'Revoking API Key...',
    successMessage: 'API Key revoked!',
    errorMessage(error) {
      try {
        if (error instanceof Error) {
          return String(error.message);
        }
        return `Failed to revoke API Key ${String(error)}`;
      } catch (_err) {
        console.warn(_err);
        return 'Failed to revoke API Key';
      }
    },
  });

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>Revoke</Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px] [&>.dialog-close]:hidden">
        <form
          onSubmit={(event) => {
            event.preventDefault();
            mutate(keyId);
          }}
        >
          <DialogHeader>
            <DialogTitle>Revoke Token</DialogTitle>
            <DialogDescription>
              Are you sure you want to revoke this token? This action is
              irreversible.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <input type="hidden" name="keyId" value={keyId} />
            <Button
              variant="destructive"
              type="submit"
              aria-disabled={isLoading}
            >
              {isLoading ? 'Revoking API Key...' : 'Yes, revoke'}
            </Button>
            <Button
              type="button"
              variant="outline"
              onClick={() => {
                setOpen(false);
              }}
            >
              Cancel
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};
