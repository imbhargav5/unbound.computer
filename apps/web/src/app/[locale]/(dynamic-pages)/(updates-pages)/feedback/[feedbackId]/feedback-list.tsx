import { Suspense } from "react";
import { Link } from "@/components/intl-link";
import { Pagination } from "@/components/pagination-ui";
import { Badge } from "@/components/ui/badge";
import type { DBTable } from "@/types";
import { cn } from "@/utils/cn";
import { statusConfig, typeConfig } from "@/utils/feedback";
import { getTypeIcon } from "@/utils/feedback-icons";
import { FeedbackAvatarServer } from "./feedback-avatar-server";
import {
  FeedbackCommentCountFallback,
  FeedbackCommentCountServer,
} from "./feedback-comment-count-server";
import {
  FeedbackReactionCountFallback,
  FeedbackReactionCountServer,
} from "./feedback-reaction-count-server";
import type { FiltersSchema } from "./schema";

interface FeedbackItemProps {
  feedback: DBTable<"marketing_feedback_threads"> & {
    comment_count: number;
    reaction_count: number;
  };
  filters: FiltersSchema;
}

function FeedbackItem({ feedback, filters }: FeedbackItemProps) {
  const searchParams = new URLSearchParams();
  if (filters.page) searchParams.append("page", filters.page.toString());
  const href = `/feedback/${feedback.id}?${searchParams.toString()}`;

  const status = statusConfig[feedback.status];
  const type = typeConfig[feedback.type];

  return (
    <Link className="block" href={href}>
      <article
        className="group rounded-lg border bg-card p-5 transition-colors hover:border-foreground/20"
        data-feedback-id={feedback.id}
        data-testid="feedback-item"
      >
        {/* Top Row: Title + Badges */}
        <div className="flex flex-wrap items-start justify-between gap-3">
          <h3 className="line-clamp-1 font-medium text-base text-foreground leading-snug">
            {feedback.title}
          </h3>
          <div className="flex shrink-0 items-center gap-2">
            {status && (
              <Badge className={cn(status.className)} variant="outline">
                {status.label}
              </Badge>
            )}
            {type && (
              <Badge
                className={cn("flex items-center gap-1", type.className)}
                variant="outline"
              >
                {getTypeIcon(feedback.type)}
                {type.label}
              </Badge>
            )}
          </div>
        </div>

        {/* Description */}
        <p className="mt-2.5 line-clamp-2 text-muted-foreground text-sm leading-relaxed">
          {feedback.content}
        </p>

        {/* Bottom Row: Author + Engagement */}
        <div className="mt-4 flex flex-wrap items-center justify-between gap-4">
          <FeedbackAvatarServer feedback={feedback} />

          {/* Engagement */}
          <div className="flex items-center gap-4 text-muted-foreground text-sm">
            <Suspense fallback={<FeedbackCommentCountFallback />}>
              <FeedbackCommentCountServer feedbackId={feedback.id} />
            </Suspense>
            <Suspense fallback={<FeedbackReactionCountFallback />}>
              <FeedbackReactionCountServer feedbackId={feedback.id} />
            </Suspense>
          </div>
        </div>
      </article>
    </Link>
  );
}

interface FeedbackListProps {
  feedbacks: Array<
    DBTable<"marketing_feedback_threads"> & {
      comment_count: number;
      reaction_count: number;
    }
  >;
  totalPages: number;
  filters: FiltersSchema;
  userType: "admin" | "loggedIn" | "anon";
}

function FeedbackListContent({
  feedbacks,
  totalPages,
  filters,
  userType,
}: FeedbackListProps) {
  const emptyStateMessages = {
    admin: "You must be logged in to view feedback.",
    loggedIn: "You haven't submitted any feedback yet.",
    anon: "No public feedbacks found.",
  };

  return (
    <div className="flex flex-col space-y-4" data-testid="feedback-list">
      {feedbacks.length > 0 ? (
        <div className="space-y-3">
          {feedbacks.map((feedback) => (
            <FeedbackItem
              feedback={feedback}
              filters={filters}
              key={feedback.id}
            />
          ))}
        </div>
      ) : (
        <div className="flex h-48 w-full items-center justify-center rounded-lg border bg-card p-6">
          <div className="flex flex-col items-center gap-1.5 text-center">
            <h3 className="font-semibold text-sm">No Feedbacks Available</h3>
            <p className="text-muted-foreground text-xs">
              {emptyStateMessages[userType]}
            </p>
          </div>
        </div>
      )}

      {totalPages > 1 && <Pagination totalPages={totalPages} />}
    </div>
  );
}

export function FeedbackList(props: FeedbackListProps) {
  return (
    <Suspense fallback={<div>Loading feedback list...</div>}>
      <FeedbackListContent {...props} />
    </Suspense>
  );
}
