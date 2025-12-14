import { MessageSquare } from "lucide-react";
import { getAnonUserFeedbackCommentsCountByThreadId } from "@/data/anon/marketing-feedback";

export function FeedbackCommentCountFallback() {
  return (
    <span className="flex items-center gap-1.5">
      <MessageSquare className="h-4 w-4" />
      <span>-</span>
    </span>
  );
}

export async function FeedbackCommentCountServer({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const count = await getAnonUserFeedbackCommentsCountByThreadId(feedbackId);
  return (
    <span className="flex items-center gap-1.5 transition-colors group-hover:text-foreground">
      <MessageSquare className="h-4 w-4" />
      <span>{count}</span>
    </span>
  );
}
