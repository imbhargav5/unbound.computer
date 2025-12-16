import { notFound } from "next/navigation";
import { adminGetInternalFeedbackById } from "@/data/admin/marketing-feedback";
import { userRoles } from "@/utils/user-types";
import { AddComment } from "../../add-comment";
import { FeedbackActionsDropdown } from "../../feedback-actions-dropdown";
import { AdminFeedbackComments } from "../comments/admin-feedback-comments";
import { CommentsSection } from "../shared/comments-section";
import { FeedbackBadges } from "../shared/feedback-badges";
import { FeedbackCard } from "../shared/feedback-card";
import { FeedbackHeader } from "../shared/feedback-header";

interface AdminFeedbackPageContentProps {
  feedbackId: string;
}

export async function AdminFeedbackPageContent({
  feedbackId,
}: AdminFeedbackPageContentProps) {
  const feedback = await adminGetInternalFeedbackById(feedbackId);

  if (!feedback) {
    return notFound();
  }

  return (
    <div className="space-y-6">
      {/* Main Content Card */}
      <FeedbackCard>
        {/* Badges with admin actions */}
        <FeedbackBadges
          actions={
            <FeedbackActionsDropdown
              feedback={feedback}
              userRole={userRoles.ADMIN}
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
      </FeedbackCard>

      {/* Comments Section */}
      <CommentsSection>
        <AdminFeedbackComments feedbackId={feedback.id} />

        {/* Add Comment - Admin can always comment */}
        <div className="mt-6 border-t pt-6">
          <AddComment feedbackId={feedback.id} />
        </div>
      </CommentsSection>
    </div>
  );
}
