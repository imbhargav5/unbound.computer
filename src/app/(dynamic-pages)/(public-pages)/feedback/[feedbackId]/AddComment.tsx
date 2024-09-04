'use client';

import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { addCommentToInternalFeedbackThreadAction } from '@/data/feedback';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';

import { Send } from 'lucide-react';
import { useState } from 'react';

function AddComment({
  feedbackId,
  defaultValue = '',
}: {
  feedbackId: string;
  defaultValue?: string;
}) {
  const [content, setContent] = useState(defaultValue);

  const { mutate, isLoading } = useSAToastMutation(
    async () => {
      return addCommentToInternalFeedbackThreadAction({ feedbackId, content });
    },
    {
      loadingMessage: 'Adding Comment',
      successMessage: 'Successfully added your comment',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to add comment ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to add comment';
        }
      },
      onSuccess: () => {
        setContent('');
      },
    },
  );

  return (
    <div className="grid w-full gap-2" data-testid="add-comment-form">
      <Textarea
        name="comment-area"
        className='resize-none'
        placeholder="Type your message here."
        value={content}
        disabled={isLoading}
        onChange={(e) => setContent(e.target.value)}
      />
      <Button
        name="add-comment-button"
        disabled={isLoading || content.length === 0}
        onClick={() => {
          if (content.length > 0) {
            mutate();
          }
        }}
      >
        <Send className="h-4 w-4 mr-2" />
        Add Comment
      </Button>
    </div>
  );
}

export default AddComment;
