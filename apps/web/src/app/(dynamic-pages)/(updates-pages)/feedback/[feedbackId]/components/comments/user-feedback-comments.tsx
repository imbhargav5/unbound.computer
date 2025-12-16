import { Suspense } from "react";
import { getInternalFeedbackComments } from "@/data/user/marketing-feedback";
import { CommentsList } from "../shared/comments-list";
import { FeedbackCommentsFallback } from "../shared/feedback-comments-fallback";

async function UserCommentsList({ feedbackId }: { feedbackId: string }) {
  const feedbackComments = await getInternalFeedbackComments(feedbackId);

  return (
    <CommentsList
      comments={feedbackComments}
      testId="logged-in-user-feedback-comments"
    />
  );
}

export async function UserFeedbackComments({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const feedbackComments = await getInternalFeedbackComments(feedbackId);
  const count = feedbackComments.length;

  return (
    <>
      <h2 className="mb-6 font-semibold text-base text-foreground">
        Comments ({count})
      </h2>
      <Suspense fallback={<FeedbackCommentsFallback />}>
        <UserCommentsList feedbackId={feedbackId} />
      </Suspense>
    </>
  );
}
