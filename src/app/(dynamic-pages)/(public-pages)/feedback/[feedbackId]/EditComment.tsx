'use client';

import { Button } from '@/components/Button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { Textarea } from '@/components/ui/textarea';
import { ownerUpdateFeedbackCommentAction } from '@/data/feedback';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { PenLine, Send } from 'lucide-react';
import { useState } from 'react';

function EditComment({
  feedbackId,
  commentId,
  userId,
  defaultValue = '',
}: {
  feedbackId: string;
  commentId: string;
  userId: string;
  defaultValue?: string;
}) {
  const [open, setOpen] = useState(false);
  const [comment, setComment] = useState(defaultValue);
  const { mutate, isLoading } = useSAToastMutation(
    async () => {
      return await ownerUpdateFeedbackCommentAction({
        feedbackId,
        feedbackCommentOwnerId: userId,
        commentId,
        content: comment,
      });
    },
    {
      loadingMessage: 'Adding Comment',
      successMessage: 'Successfully added your comment',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to update comment ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to update comment';
        }
      },
      onSuccess: () => {
        setComment('');
        setOpen(false);
      },
    },
  );
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger>
        <PenLine className="ml-auto h-4 w-4" />
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Update your comment.</DialogTitle>
          <DialogDescription>
            This action will update your comment.
          </DialogDescription>
        </DialogHeader>
        <div className="grid w-full gap-2">
          <Textarea
            placeholder="Type your message here."
            value={comment}
            onChange={(e) => setComment(e.target.value)}
          />
        </div>
        <DialogFooter>
          <Button
            disabled={isLoading || comment.length === 0}
            onClick={() => {
              if (comment.length > 0) {
                mutate();
              }
            }}
          >
            <Send className="h-4 w-4 mr-2" />
            Update message
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default EditComment;
