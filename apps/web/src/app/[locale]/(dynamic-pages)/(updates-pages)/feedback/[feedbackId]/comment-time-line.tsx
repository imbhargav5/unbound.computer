import { formatDistance } from "date-fns";
import { Suspense } from "react";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { appAdminGetInternalFeedbackComments } from "@/data/admin/marketing-feedback";
import { anonGetUserProfile } from "@/data/user/elevated-queries";
import { getInternalFeedbackComments } from "@/data/user/marketing-feedback";
import type { DBTable } from "@/types";
import { serverGetUserType } from "@/utils/server/server-get-user-type";
import { userRoles } from "@/utils/user-types";

function FeedbackCommentsFallback() {
  return (
    <div className="space-y-5">
      {[1, 2, 3].map((i) => (
        <div className="flex gap-3" key={i}>
          <Skeleton className="h-8 w-8 shrink-0 rounded-full" />
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-3 w-16" />
            </div>
            <Skeleton className="mt-2 h-12 w-full" />
          </div>
        </div>
      ))}
    </div>
  );
}

async function CommentCard({
  comment,
}: {
  comment: DBTable<"marketing_feedback_comments">;
}) {
  const userProfile = await anonGetUserProfile(comment.user_id);

  return (
    <div
      className="flex gap-3"
      data-comment-id={comment.id}
      data-testid={`comment-timeline-item-${comment.id}`}
    >
      <Avatar className="h-8 w-8 shrink-0">
        <AvatarImage
          alt={userProfile?.full_name ?? "User"}
          src={userProfile?.avatar_url ?? undefined}
        />
        <AvatarFallback className="bg-muted font-medium text-muted-foreground text-xs">
          {userProfile?.full_name?.charAt(0) ?? "U"}
        </AvatarFallback>
      </Avatar>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="font-medium text-foreground text-sm">
            {userProfile?.full_name ?? "User"}
          </span>
          <span className="text-muted-foreground text-xs">
            {formatDistance(new Date(comment.created_at), new Date(), {
              addSuffix: true,
            })}
          </span>
        </div>
        <p className="mt-1 text-muted-foreground text-sm leading-relaxed">
          {comment.content}
        </p>
      </div>
    </div>
  );
}

function CommentsList({
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

async function LoggedInUserFeedbackComments({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const feedbackComments = await getInternalFeedbackComments(feedbackId);

  return (
    <CommentsList
      comments={feedbackComments}
      testId="logged-in-user-feedback-comments"
    />
  );
}

async function AnonUserFeedbackComments({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const feedbackComments = await getInternalFeedbackComments(feedbackId);

  return (
    <CommentsList
      comments={feedbackComments}
      testId="anon-user-feedback-comments"
    />
  );
}

async function AdminFeedbackComments({ feedbackId }: { feedbackId: string }) {
  const feedbackComments =
    await appAdminGetInternalFeedbackComments(feedbackId);

  return (
    <CommentsList
      comments={feedbackComments}
      testId="admin-user-feedback-comments"
    />
  );
}

export async function SuspendedFeedbackComments({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const userRoleType = await serverGetUserType();
  const feedbackComments = await getInternalFeedbackComments(feedbackId);
  const count = feedbackComments.length;

  return (
    <>
      <h2 className="mb-6 font-semibold text-base text-foreground">
        Comments ({count})
      </h2>
      <Suspense fallback={<FeedbackCommentsFallback />}>
        {userRoleType === userRoles.ANON && (
          <AnonUserFeedbackComments feedbackId={feedbackId} />
        )}
        {userRoleType === userRoles.ADMIN && (
          <AdminFeedbackComments feedbackId={feedbackId} />
        )}
        {userRoleType === userRoles.USER && (
          <LoggedInUserFeedbackComments feedbackId={feedbackId} />
        )}
      </Suspense>
    </>
  );
}
