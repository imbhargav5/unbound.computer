'use client';

import { zodResolver } from '@hookform/resolvers/zod';
import { useAction } from 'next-safe-action/hooks';
import { Fragment, startTransition, useOptimistic, useRef } from 'react';
import { useForm } from 'react-hook-form';
import { toast } from 'sonner';
import { z } from 'zod';

import { T } from '@/components/ui/Typography';
import { Button } from '@/components/ui/button';
import { SelectSeparator } from '@/components/ui/select';
import { Textarea } from '@/components/ui/textarea';
import { createProjectCommentAction } from '@/data/user/projects';

const addCommentSchema = z.object({
  text: z.string().min(1),
});

type AddCommentSchema = z.infer<typeof addCommentSchema>;

type InFlightComment = {
  children: JSX.Element;
  id: string | number;
};

type CreateProjectCommentActionResult = Awaited<ReturnType<typeof createProjectCommentAction>>;

export const CommentInput = ({ projectId }: { projectId: string }): JSX.Element => {
  const [commentsInFlight, addCommentToFlight] = useOptimistic<
    InFlightComment[],
    InFlightComment
  >([], (state, newMessage) => [...state, newMessage]);

  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute: addComment, status } = useAction(createProjectCommentAction, {
    onExecute: () => {
      toastRef.current = toast.loading('Adding comment...');
    },
    onSuccess: (result) => {
      toast.success('Comment added!', { id: toastRef.current });
      toastRef.current = undefined;
      startTransition(() => {
        if (result.data) {
          addCommentToFlight({
            children: result.data.commentList,
            id: result.data.id,
          });
        }
      });
    },
    onError: ({ error }) => {
      const errorMessage = error.serverError ?? 'Failed to add comment';
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const { handleSubmit, setValue, register } = useForm<AddCommentSchema>({
    resolver: zodResolver(addCommentSchema),
    defaultValues: {
      text: '',
    },
  });

  return (
    <>
      <form
        onSubmit={handleSubmit((data) => {
          addComment({ projectId, text: data.text });
          setValue('text', '');
        })}
      >
        <div className="space-y-3">
          <Textarea
            id="text"
            placeholder="Share your thoughts"
            className="p-3 h-24 rounded-lg"
            {...register('text')}
          />
          <div className="flex justify-end space-x-2">
            <Button disabled={status === 'executing'} variant="outline" type="reset">
              Reset
            </Button>
            <Button disabled={status === 'executing'} type="submit">
              {status === 'executing' ? 'Adding comment...' : 'Add comment'}
            </Button>
          </div>
        </div>
      </form>
      <div className="mt-8 mb-4">
        <SelectSeparator />
      </div>
      {commentsInFlight.map((comment) => (
        <div className="space-y-2" key={comment.id}>
          <T.Subtle className="text-xs italic">Sending comment</T.Subtle>
          <Fragment key={comment.id}>{comment.children}</Fragment>
        </div>
      ))}
    </>
  );
};
