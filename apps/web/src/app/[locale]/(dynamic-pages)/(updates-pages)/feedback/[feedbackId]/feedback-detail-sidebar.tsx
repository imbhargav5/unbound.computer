import { formatDistance } from "date-fns";
import {
  Calendar,
  CircleDot,
  Flag,
  Info,
  Layout,
  MessageSquare,
  Tag,
  ThumbsUp,
  User,
} from "lucide-react";
import { Suspense } from "react";
import { Link } from "@/components/intl-link";
import { RecentPublicFeedback } from "@/components/recent-public-feedback";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import {
  adminGetInternalFeedbackById,
  getBoardById,
  getFeedbackBoards,
} from "@/data/admin/marketing-feedback";
import { getAnonUserFeedbackById } from "@/data/anon/marketing-feedback";
import { anonGetUserProfile } from "@/data/user/elevated-queries";
import { getLoggedInUserFeedbackById } from "@/data/user/marketing-feedback";
import type { UserRole } from "@/types/user-types";
import { cn } from "@/utils/cn";
import {
  NEW_PRIORITY_OPTIONS,
  statusConfig,
  typeConfig,
} from "@/utils/feedback";
import { BoardSelectionDialog } from "./board-selection-dialog";

function RecentFeedbackSkeleton() {
  return (
    <div className="space-y-2">
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-full" />
    </div>
  );
}

async function getFeedback(feedbackId: string, userRoleType: UserRole) {
  if (userRoleType === "anon") {
    return await getAnonUserFeedbackById(feedbackId);
  }
  if (userRoleType === "user") {
    return await getLoggedInUserFeedbackById(feedbackId);
  }
  if (userRoleType === "admin") {
    return await adminGetInternalFeedbackById(feedbackId);
  }
}

export async function FeedbackDetailSidebar({
  feedbackId,
  userRole,
}: {
  feedbackId: string;
  userRole: UserRole;
}) {
  const feedback = await getFeedback(feedbackId, userRole);
  const boards = userRole === "admin" ? await getFeedbackBoards() : null;

  if (!feedback) {
    throw new Error("Feedback not found");
  }

  const board = feedback.board_id
    ? await getBoardById(feedback.board_id)
    : null;

  const userProfile = await anonGetUserProfile(feedback.user_id);
  const status = statusConfig[feedback.status];
  const type = typeConfig[feedback.type];
  const priority = NEW_PRIORITY_OPTIONS.find(
    (p) => p.value === feedback.priority
  );

  const feedbackWithCounts = feedback as typeof feedback & {
    comment_count?: number;
    reaction_count?: number;
  };
  const commentCount = feedbackWithCounts.comment_count ?? 0;
  const reactionCount = feedbackWithCounts.reaction_count ?? 0;

  return (
    <div className="w-full shrink-0 space-y-4 lg:w-80">
      {/* Details Card */}
      <div className="rounded-lg border bg-card p-5">
        <h3 className="mb-4 font-semibold text-foreground text-sm">Details</h3>

        <div className="space-y-4">
          {/* Board Selection (Admin Only) */}
          {userRole === "admin" ? (
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-2 text-muted-foreground text-sm">
                <Layout className="h-4 w-4 opacity-50" />
                Board
              </span>
              <BoardSelectionDialog
                boards={boards || []}
                currentBoardId={feedback.board_id}
                feedbackId={feedbackId}
              />
            </div>
          ) : (
            board && (
              <div className="flex items-center justify-between">
                <span className="flex items-center gap-2 text-muted-foreground text-sm">
                  <Layout className="h-4 w-4 opacity-50" />
                  Board
                </span>
                <Link href={`/feedback/boards/${board.slug}`}>
                  <Badge
                    className="cursor-pointer transition-colors hover:bg-accent"
                    variant="outline"
                  >
                    {board.title}
                  </Badge>
                </Link>
              </div>
            )
          )}

          {/* Status Row */}
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-muted-foreground text-sm">
              <CircleDot className="h-4 w-4 opacity-50" />
              Status
            </span>
            {status && (
              <Badge
                className={cn(status.className)}
                data-testid="feedback-status-badge"
                variant="outline"
              >
                {status.label}
              </Badge>
            )}
          </div>

          {/* Type Row */}
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-muted-foreground text-sm">
              <Tag className="h-4 w-4 opacity-50" />
              Category
            </span>
            {type && (
              <Badge
                className={cn(type.className)}
                data-testid="feedback-type-badge"
                variant="outline"
              >
                {type.label}
              </Badge>
            )}
          </div>

          {/* Priority Row */}
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-muted-foreground text-sm">
              <Flag className="h-4 w-4 opacity-50" />
              Priority
            </span>
            {priority && (
              <Badge data-testid="feedback-priority-badge" variant="outline">
                {priority.label}
              </Badge>
            )}
          </div>

          <Separator />

          {/* Author Row */}
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-muted-foreground text-sm">
              <User className="h-4 w-4 opacity-50" />
              Author
            </span>
            <div className="flex items-center gap-2">
              <Avatar className="h-5 w-5">
                <AvatarImage
                  alt="User avatar"
                  src={userProfile?.avatar_url ?? undefined}
                />
                <AvatarFallback className="bg-muted font-medium text-[10px]">
                  {userProfile?.full_name?.charAt(0) ?? "U"}
                </AvatarFallback>
              </Avatar>
              <span className="font-medium text-foreground text-sm">
                {userProfile?.full_name ?? "User"}
              </span>
            </div>
          </div>

          {/* Created Row */}
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-muted-foreground text-sm">
              <Calendar className="h-4 w-4 opacity-50" />
              Created
            </span>
            <span className="text-foreground text-sm">
              {formatDistance(new Date(feedback.created_at), new Date(), {
                addSuffix: true,
              })}
            </span>
          </div>

          <Separator />

          {/* Stats Row */}
          <div className="flex items-center gap-6">
            <div className="flex items-center gap-2 text-muted-foreground text-sm">
              <MessageSquare className="h-4 w-4" />
              <span>{commentCount} comments</span>
            </div>
            <div className="flex items-center gap-2 text-muted-foreground text-sm">
              <ThumbsUp className="h-4 w-4" />
              <span>{reactionCount} upvotes</span>
            </div>
          </div>
        </div>
      </div>

      {/* Recent Feedback Card */}
      <div className="rounded-lg border bg-card p-5">
        <h3 className="mb-4 font-semibold text-foreground text-sm">
          Recent Feedback
        </h3>
        <Suspense fallback={<RecentFeedbackSkeleton />}>
          <RecentPublicFeedback />
        </Suspense>
      </div>

      {/* Community Guidelines Card */}
      <div className="rounded-lg border bg-card p-5">
        <h3 className="mb-3 flex items-center gap-2 font-semibold text-foreground text-sm">
          <Info className="h-4 w-4 text-muted-foreground" />
          Community Guidelines
        </h3>
        <p className="text-muted-foreground text-sm leading-relaxed">
          Please remember that this is a public forum. We kindly ask all users
          to conduct themselves in a civil and respectful manner. Let&apos;s
          foster a positive environment for everyone.
        </p>
      </div>
    </div>
  );
}
