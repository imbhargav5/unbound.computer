import { EyeIcon, EyeOffIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import type { Enum } from "@/types";
import { cn } from "@/utils/cn";
import { statusConfig, typeConfig } from "@/utils/feedback";
import { getTypeIcon } from "@/utils/feedback-icons";

interface FeedbackBadgesProps {
  status: Enum<"marketing_feedback_thread_status">;
  type: Enum<"marketing_feedback_thread_type">;
  isPubliclyVisible: boolean;
  showPrivacyBadge?: boolean;
  actions?: React.ReactNode;
}

export function FeedbackBadges({
  status,
  type,
  isPubliclyVisible,
  showPrivacyBadge = true,
  actions,
}: FeedbackBadgesProps) {
  const statusInfo = statusConfig[status];
  const typeInfo = typeConfig[type];

  return (
    <div className="mb-4 flex flex-wrap items-start gap-3">
      {/* Status Badge */}
      {statusInfo && (
        <Badge className={cn(statusInfo.className)} variant="outline">
          {statusInfo.label}
        </Badge>
      )}

      {/* Type Badge */}
      {typeInfo && (
        <Badge
          className={cn("flex items-center gap-1", typeInfo.className)}
          variant="outline"
        >
          {getTypeIcon(type)}
          {typeInfo.label}
        </Badge>
      )}

      {/* Visibility Badge and Actions */}
      <div
        className="ml-auto flex items-center gap-3"
        data-testid="feedback-visibility"
      >
        {showPrivacyBadge && (
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                {isPubliclyVisible ? (
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
                {isPubliclyVisible
                  ? "This feedback is visible to the public"
                  : "This feedback is private and only visible to you and admins"}
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        )}

        {/* Actions Slot */}
        {actions}
      </div>
    </div>
  );
}
