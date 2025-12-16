import { Bug, EyeIcon, EyeOffIcon, MessageSquare, Zap } from "lucide-react";
import { notFound } from "next/navigation";
import { Badge } from "@/components/ui/badge";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { adminGetInternalFeedbackById } from "@/data/admin/marketing-feedback";
import { cn } from "@/utils/cn";
import { statusConfig, typeConfig } from "@/utils/feedback";
import { serverGetClaimType } from "@/utils/server/server-get-user-type";
import { AddComment } from "./add-comment";
import { SuspendedFeedbackComments } from "./comment-time-line";
import { FeedbackActionsDropdown } from "./feedback-actions-dropdown";
import { FeedbackAvatarServer } from "./feedback-avatar-server";

const typeIcons: Record<string, React.ReactNode> = {
  bug: <Bug className="h-3 w-3" />,
  feature_request: <Zap className="h-3 w-3" />,
  general: <MessageSquare className="h-3 w-3" />,
};

async function AdminUserFeedbackdetail({ feedbackId }: { feedbackId: string }) {
  const userRoleType = await serverGetClaimType();
  const feedback = await adminGetInternalFeedbackById(feedbackId);

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
          {status ? (
            <Badge className={cn(status.className)} variant="outline">
              {status.label}
            </Badge>
          ) : null}
          {type ? (
            <Badge
              className={cn("flex items-center gap-1", type.className)}
              variant="outline"
            >
              {typeIcons[feedback.type]}
              {type.label}
            </Badge>
          ) : null}
          {/* Visibility Badge */}
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                {feedback.is_publicly_visible ? (
                  <Badge
                    className="flex cursor-help items-center gap-1.5 border-green-200 bg-green-50 text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-400"
                    variant="outline"
                  >
                    <EyeIcon className="h-3 w-3" />
                    Public
                  </Badge>
                ) : (
                  <Badge
                    className="flex cursor-help items-center gap-1.5"
                    variant="outline"
                  >
                    <EyeOffIcon className="h-3 w-3" />
                    Private
                  </Badge>
                )}
              </TooltipTrigger>
              <TooltipContent>
                {feedback.is_publicly_visible
                  ? "This feedback is visible to the public"
                  : "This feedback is only visible to admins and the user who created it"}
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>

          {/* Actions Dropdown */}
          <div className="ml-auto">
            <FeedbackActionsDropdown
              feedback={feedback}
              userRole={userRoleType}
            />
          </div>
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

      {/* Comments Section */}
      <div className="rounded-lg border bg-card p-6">
        <SuspendedFeedbackComments feedbackId={feedback.id} />

        {/* Add Comment - Admin can always comment */}
        <div className="mt-6 border-t pt-6">
          <AddComment feedbackId={feedback.id} />
        </div>
      </div>
    </div>
  );
}

export default AdminUserFeedbackdetail;
