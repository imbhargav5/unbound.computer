import { ThumbsUp } from "lucide-react";
import { getAnonUserFeedbackReactionsCountByThreadId } from "@/data/anon/marketing-feedback";

export function FeedbackReactionCountFallback() {
  return (
    <span className="flex items-center gap-1.5">
      <ThumbsUp className="h-4 w-4" />
      <span>-</span>
    </span>
  );
}

export async function FeedbackReactionCountServer({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const count = await getAnonUserFeedbackReactionsCountByThreadId(feedbackId);
  return (
    <span className="flex items-center gap-1.5 transition-colors group-hover:text-foreground">
      <ThumbsUp className="h-4 w-4" />
      <span>{count}</span>
    </span>
  );
}
