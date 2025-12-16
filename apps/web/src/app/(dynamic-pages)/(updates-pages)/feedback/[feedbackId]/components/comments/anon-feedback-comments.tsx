import { Suspense } from "react";
import { getAnonFeedbackComments } from "@/data/anon/marketing-feedback";
import { CommentsList } from "../shared/comments-list";
import { FeedbackCommentsFallback } from "../shared/feedback-comments-fallback";

async function AnonCommentsList({ feedbackId }: { feedbackId: string }) {
  const feedbackComments = await getAnonFeedbackComments(feedbackId);

  return (
    <CommentsList
      comments={feedbackComments}
      testId="anon-user-feedback-comments"
    />
  );
}

export async function AnonFeedbackComments({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const feedbackComments = await getAnonFeedbackComments(feedbackId);
  const count = feedbackComments.length;

  return (
    <>
      <h2 className="mb-6 font-semibold text-base text-foreground">
        Comments ({count})
      </h2>
      <Suspense fallback={<FeedbackCommentsFallback />}>
        <AnonCommentsList feedbackId={feedbackId} />
      </Suspense>
    </>
  );
}
