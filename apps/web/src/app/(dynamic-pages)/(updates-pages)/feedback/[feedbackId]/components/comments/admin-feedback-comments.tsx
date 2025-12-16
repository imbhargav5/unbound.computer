import { Suspense } from "react";
import { appAdminGetInternalFeedbackComments } from "@/data/admin/marketing-feedback";
import { CommentsList } from "../shared/comments-list";
import { FeedbackCommentsFallback } from "../shared/feedback-comments-fallback";

async function AdminCommentsList({ feedbackId }: { feedbackId: string }) {
  const feedbackComments =
    await appAdminGetInternalFeedbackComments(feedbackId);

  return (
    <CommentsList
      comments={feedbackComments}
      testId="admin-user-feedback-comments"
    />
  );
}

export async function AdminFeedbackComments({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const feedbackComments =
    await appAdminGetInternalFeedbackComments(feedbackId);
  const count = feedbackComments.length;

  return (
    <>
      <h2 className="mb-6 font-semibold text-base text-foreground">
        Comments ({count})
      </h2>
      <Suspense fallback={<FeedbackCommentsFallback />}>
        <AdminCommentsList feedbackId={feedbackId} />
      </Suspense>
    </>
  );
}
