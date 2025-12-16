"use client";

import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { addCommentToInternalFeedbackThreadAction } from "@/data/feedback";

interface AddCommentProps {
  feedbackId: string;
  defaultValue?: string;
}

function AddComment({ feedbackId, defaultValue = "" }: AddCommentProps) {
  const [content, setContent] = useState<string>(defaultValue);
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute, status } = useAction(
    addCommentToInternalFeedbackThreadAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Adding comment...");
      },
      onSuccess: () => {
        toast.success("Comment added successfully", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        setContent("");
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to add comment";
        toast.error(errorMessage, { id: toastRef.current });
        toastRef.current = undefined;
      },
    }
  );

  const handleAddComment = () => {
    if (content.length > 0) {
      execute({ feedbackId, content });
    }
  };

  return (
    <div data-testid="add-comment-form">
      <h3 className="mb-3 font-medium text-foreground text-sm">
        Add a comment
      </h3>
      <Textarea
        className="min-h-24 resize-none"
        disabled={status === "executing"}
        name="comment-area"
        onChange={(e) => setContent(e.target.value)}
        placeholder="Share your thoughts or ask a question..."
        value={content}
      />
      <div className="mt-3 flex justify-end">
        <Button
          disabled={status === "executing" || content.length === 0}
          name="add-comment-button"
          onClick={handleAddComment}
          size="sm"
        >
          Post Comment
        </Button>
      </div>
    </div>
  );
}

export { AddComment };
