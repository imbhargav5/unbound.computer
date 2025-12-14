import { notFound } from "next/navigation";
import { getAnonUserFeedbackById } from "@/data/anon/marketing-feedback";
import { AnonFeedbackComments } from "../comments/anon-feedback-comments";
import { CommentsSection } from "../shared/comments-section";
import { FeedbackBadges } from "../shared/feedback-badges";
import { FeedbackCard } from "../shared/feedback-card";
import { FeedbackHeader } from "../shared/feedback-header";

interface AnonFeedbackPageContentProps {
  feedbackId: string;
}

export async function AnonFeedbackPageContent({
  feedbackId,
}: AnonFeedbackPageContentProps) {
  const feedback = await getAnonUserFeedbackById(feedbackId);

  if (!feedback) {
    return notFound();
  }

  return (
    <div className="space-y-6">
      {/* Main Content Card */}
      <FeedbackCard>
        {/* Badges - Always public for anon users */}
        <FeedbackBadges
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

      {/* Comments Section - View only for anon users */}
      <CommentsSection>
        <AnonFeedbackComments feedbackId={feedback.id} />
      </CommentsSection>
    </div>
  );
}
