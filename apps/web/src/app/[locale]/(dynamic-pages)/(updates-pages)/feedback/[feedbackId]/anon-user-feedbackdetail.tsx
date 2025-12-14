import { Bug, EyeIcon, MessageSquare, Zap } from "lucide-react";
import { notFound } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { getAnonUserFeedbackById } from "@/data/anon/marketing-feedback";
import { cn } from "@/utils/cn";
import { statusConfig, typeConfig } from "@/utils/feedback";
import { SuspendedFeedbackComments } from "./comment-time-line";
import { FeedbackAvatarServer } from "./feedback-avatar-server";

const typeIcons: Record<string, React.ReactNode> = {
  bug: <Bug className="h-3 w-3" />,
  feature_request: <Zap className="h-3 w-3" />,
  general: <MessageSquare className="h-3 w-3" />,
};

async function AnonUserFeedbackDetail({ feedbackId }: { feedbackId: string }) {
  const feedback = await getAnonUserFeedbackById(feedbackId);

  if (!feedback) {
    return notFound();
  }

  const status = statusConfig[feedback.status];
  const type = typeConfig[feedback.type];

  return (
    <div className="space-y-6">
      {/* Main Content Card */}
      <div className="rounded-lg border bg-card p-6">
        {/* Badges at top */}
        <div className="mb-4 flex flex-wrap items-start gap-3">
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
              {typeIcons[feedback.type]}
              {type.label}
            </Badge>
          )}
          {/* Visibility Badge - Always Public for anon users */}
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Badge
                  className="flex cursor-help items-center gap-1.5 border-green-200 bg-green-50 text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-400"
                  variant="outline"
                >
                  <EyeIcon className="h-3 w-3" />
                  Public
                </Badge>
              </TooltipTrigger>
              <TooltipContent>
                This feedback is visible to the public
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
          {/* No Actions Dropdown for anon users */}
        </div>

        {/* Title */}
        <h1 className="mb-4 font-semibold text-foreground text-xl leading-snug">
          {feedback.title}
        </h1>

        {/* Author Info */}
        <div className="mb-6">
          <FeedbackAvatarServer feedback={feedback} />
        </div>

        {/* Description */}
        <div className="prose prose-sm prose-neutral dark:prose-invert max-w-none">
          <p className="text-muted-foreground text-sm leading-relaxed">
            {feedback.content}
          </p>
        </div>
      </div>

      {/* Comments Section - View only for anon users */}
      <div className="rounded-lg border bg-card p-6">
        <SuspendedFeedbackComments feedbackId={feedback.id} />
        {/* No AddComment for anon users */}
      </div>
    </div>
  );
}

export default AnonUserFeedbackDetail;
