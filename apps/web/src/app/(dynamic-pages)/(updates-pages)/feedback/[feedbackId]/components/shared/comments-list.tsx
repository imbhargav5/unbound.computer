import { Separator } from "@/components/ui/separator";
import type { DBTable } from "@/types";
import { CommentCard } from "./comment-card";

export function CommentsList({
  comments,
  testId,
}: {
  comments: DBTable<"marketing_feedback_comments">[];
  testId: string;
}) {
  if (!comments.length) {
    return (
      <p className="text-muted-foreground text-sm">
        No comments yet. Be the first to share your thoughts!
      </p>
    );
  }

  return (
    <div className="space-y-5" data-testid={testId}>
      {comments.map((comment, index) => (
        <div key={comment.id}>
          <CommentCard comment={comment} />
          {index < comments.length - 1 && <Separator className="mt-5" />}
        </div>
      ))}
    </div>
  );
}
