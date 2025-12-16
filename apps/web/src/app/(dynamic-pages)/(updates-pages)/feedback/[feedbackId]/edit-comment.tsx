"use client";

import { PenLine, Send } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { ownerUpdateMarketingFeedbackCommentAction } from "@/data/feedback";

interface EditCommentProps {
  feedbackId: string;
  commentId: string;
  userId: string;
  defaultValue?: string;
}

function EditComment({
  feedbackId,
  commentId,
  userId,
  defaultValue = "",
}: EditCommentProps) {
  const [open, setOpen] = useState<boolean>(false);
  const [comment, setComment] = useState<string>(defaultValue);
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute, isPending } = useAction(
    ownerUpdateMarketingFeedbackCommentAction,
    {
      onExecute: () => {
        toastRef.current = toast.loading("Updating comment...");
      },
      onSuccess: () => {
        toast.success("Successfully updated your comment", {
          id: toastRef.current,
        });
        toastRef.current = undefined;
        setComment("");
        setOpen(false);
      },
      onError: ({ error }) => {
        const errorMessage = error.serverError ?? "Failed to update comment";
        toast.error(errorMessage, { id: toastRef.current });
        toastRef.current = undefined;
      },
    }
  );

  const handleUpdateComment = () => {
    if (comment.length > 0) {
      execute({
        feedbackId,
        feedbackCommentOwnerId: userId,
        commentId,
        content: comment,
      });
    }
  };

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button size="icon" variant="ghost">
          <PenLine className="h-4 w-4" />
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Update your comment</DialogTitle>
          <DialogDescription>
            This action will update your comment.
          </DialogDescription>
        </DialogHeader>
        <div className="grid w-full gap-2">
          <Textarea
            onChange={(e) => setComment(e.target.value)}
            placeholder="Type your message here."
            value={comment}
          />
        </div>
        <DialogFooter>
          <Button
            disabled={isPending || comment.length === 0}
            onClick={handleUpdateComment}
          >
            <Send className="mr-2 h-4 w-4" />
            Update message
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export { EditComment };
