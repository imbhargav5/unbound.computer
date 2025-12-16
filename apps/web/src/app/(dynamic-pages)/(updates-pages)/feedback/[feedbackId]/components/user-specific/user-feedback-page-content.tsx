import { notFound } from "next/navigation";
import {
  getLoggedInUserFeedbackById,
  getUserUpvoteStatus,
} from "@/data/user/marketing-feedback";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import { userRoles } from "@/utils/user-types";
import { AddComment } from "../../add-comment";
import { FeedbackActionsDropdown } from "../../feedback-actions-dropdown";
import { UpvoteButton } from "../../upvote-button";
import { UserFeedbackComments } from "../comments/user-feedback-comments";
import { CommentsSection } from "../shared/comments-section";
import { FeedbackBadges } from "../shared/feedback-badges";
import { FeedbackCard } from "../shared/feedback-card";
import { FeedbackHeader } from "../shared/feedback-header";

interface UserFeedbackPageContentProps {
  feedbackId: string;
}

export async function UserFeedbackPageContent({
  feedbackId,
}: UserFeedbackPageContentProps) {
  const user = await serverGetLoggedInUserClaims();
  const userId = user.sub;
  const feedback = await getLoggedInUserFeedbackById(feedbackId);

  if (!feedback) {
    return notFound();
  }

  const userHasUpvoted = await getUserUpvoteStatus(feedbackId);

  // Check if user can add comments (publicly visible feedback or owner)
  const canAddComment =
    feedback.open_for_public_discussion || feedback.user_id === userId;

  return (
    <div className="space-y-6">
      {/* Main Content Card */}
      <FeedbackCard>
        {/* Badges with actions */}
        <FeedbackBadges
          actions={
            <FeedbackActionsDropdown
              feedback={feedback}
              userRole={userRoles.USER}
            />
          }
          isPubliclyVisible={feedback.is_publicly_visible}
          status={feedback.status}
          type={feedback.type}
        />

        {/* Header with title and author */}
        <FeedbackHeader feedback={feedback} title={feedback.title} />

        {/* Description */}
        <div className="prose prose-sm prose-neutral dark:prose-invert max-w-none">
          <p className="text-muted-foreground text-sm leading-relaxed">
            {feedback.content}
          </p>
        </div>

        {/* Upvote Button */}
        <div className="mt-6 border-t pt-4">
          <UpvoteButton
            feedbackId={feedback.id}
            initialUpvoted={userHasUpvoted}
            upvoteCount={feedback.reaction_count}
          />
        </div>
      </FeedbackCard>

      {/* Comments Section */}
      <CommentsSection>
        <UserFeedbackComments feedbackId={feedback.id} />

        {/* Add Comment - Only if user has permission */}
        {canAddComment ? (
          <div className="mt-6 border-t pt-6">
            <AddComment feedbackId={feedback.id} />
          </div>
        ) : null}
      </CommentsSection>
    </div>
  );
}
