"use client";

import { ThumbsUp } from "lucide-react";
import { useAction } from "next-cool-action/hooks";
import { useOptimistic, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { toggleFeedbackUpvoteAction } from "@/data/feedback";
import { cn } from "@/utils/cn";

interface UpvoteButtonProps {
  feedbackId: string;
  initialUpvoted: boolean;
  upvoteCount: number;
}

export function UpvoteButton({
  feedbackId,
  initialUpvoted,
  upvoteCount,
}: UpvoteButtonProps) {
  const [isPending, startTransition] = useTransition();
  const [optimisticState, setOptimisticState] = useOptimistic(
    { upvoted: initialUpvoted, count: upvoteCount },
    (state) => ({
      upvoted: !state.upvoted,
      count: state.upvoted ? state.count - 1 : state.count + 1,
    })
  );

  const { execute } = useAction(toggleFeedbackUpvoteAction);

  const handleClick = () => {
    startTransition(() => {
      setOptimisticState(optimisticState);
      execute({ feedbackId });
    });
  };

  return (
    <Button
      className={cn(
        "gap-2 bg-transparent",
        optimisticState.upvoted && "text-primary"
      )}
      data-testid="upvote-button"
      disabled={isPending}
      onClick={handleClick}
      size="sm"
      variant="outline"
    >
      <ThumbsUp
        className={cn("h-4 w-4", optimisticState.upvoted && "fill-current")}
      />
      Upvote
      {optimisticState.count > 0 && (
        <span className="ml-1 text-muted-foreground" data-testid="upvote-count">
          ({optimisticState.count})
        </span>
      )}
    </Button>
  );
}
