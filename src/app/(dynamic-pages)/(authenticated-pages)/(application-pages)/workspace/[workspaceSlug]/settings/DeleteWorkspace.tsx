'use client';
import { T } from '@/components/ui/Typography';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { deleteWorkspaceAction } from '@/data/user/workspaces';
import { zodResolver } from '@hookform/resolvers/zod';
import { useAction } from 'next-safe-action/hooks';
import { useRouter } from 'next/navigation';
import { useRef, useState } from 'react';
import { useForm } from 'react-hook-form';
import { toast } from 'sonner';
import { z } from 'zod';

type DeleteWorkspaceProps = {
  workspaceTitle: string;
  workspaceId: string;
};

export const DeleteWorkspace = ({
  workspaceTitle,
  workspaceId,
}: DeleteWorkspaceProps) => {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const toastRef = useRef<string | number | undefined>(undefined);
  const { execute, isPending } = useAction(
    deleteWorkspaceAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading('Deleting workspace...');
      },
      onSuccess: () => {
        toast.success('Workspace deleted', {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        setOpen(false);
        router.push('/dashboard');
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? error.fetchError ?? 'Failed to delete workspace';
        toast.error(errorMessage, {
          id: toastRef.current,
        });
        toastRef.current = undefined;
      },
    },
  );

  type inputs = {
    workspaceTitle: string;
  };

  const formSchema = z.object({
    workspaceTitle: z
      .string()
      .refine(
        (v) => v === `delete ${workspaceTitle}`,
        `Must match "delete ${workspaceTitle}"`,
      ),
  });

  const {
    register,
    handleSubmit,
    formState: { errors, isValid },
  } = useForm<inputs>({
    resolver: zodResolver(formSchema),
  });

  const onSubmit = () => {
    execute({ workspaceId });
  };

  return (
    <div className="space-y-4">
      <T.H3>Danger Zone</T.H3>
      <div>
        <T.P>Delete your workspace</T.P>
        <T.Subtle>
          Once you delete an workspace, there is no going back. Please be
          certain.
        </T.Subtle>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogTrigger asChild>
          <Button variant={'destructive'}>Delete Organization</Button>
        </DialogTrigger>

        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Organization</DialogTitle>
            <DialogDescription>
              Type <strong> "delete {workspaceTitle}" </strong>to confirm.
            </DialogDescription>
          </DialogHeader>
          <form
            className="flex flex-col gap-4"
            onSubmit={handleSubmit(onSubmit)}
          >
            <Input type="text" {...register('workspaceTitle')} />
            {errors.workspaceTitle && (
              <p className="text-red-400 text-sm font-bold">
                {errors.workspaceTitle.message}
              </p>
            )}

            <Button
              disabled={isPending || !isValid}
              type="submit"
              variant="destructive"
              className="w-fit self-end"
            >
              {isPending ? 'Deleting...' : 'Delete'} Organization
            </Button>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
};
