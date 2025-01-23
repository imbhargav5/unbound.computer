import { RecentPublicFeedback } from "@/components/RecentPublicFeedback";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  adminGetInternalFeedbackById,
  getBoardById,
  getFeedbackBoards,
} from "@/data/admin/marketing-feedback";
import { getAnonUserFeedbackById } from "@/data/anon/marketing-feedback";
import { getLoggedInUserFeedbackById } from "@/data/user/marketing-feedback";
import { UserRole } from "@/types/userTypes";
import { serverGetUserType } from "@/utils/server/serverGetUserType";
import { Flag, Info, Layout, ListTodo, Type } from "lucide-react";
import { Suspense } from "react";
import { BoardSelectionDialog } from "./BoardSelectionDialog";
import { FeedbackAvatarServer } from "./FeedbackAvatarServer";

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
  } else if (userRoleType === "user") {
    return await getLoggedInUserFeedbackById(feedbackId);
  } else if (userRoleType === "admin") {
    return await adminGetInternalFeedbackById(feedbackId);
  }
}

export async function FeedbackDetailSidebar({
  feedbackId,
}: {
  feedbackId: string;
}) {
  const userRoleType = await serverGetUserType();
  const feedback = await getFeedback(feedbackId, userRoleType);
  const boards = userRoleType === "admin" ? await getFeedbackBoards() : null;

  if (!feedback) {
    throw new Error("Feedback not found");
  }

  const board = feedback.board_id
    ? await getBoardById(feedback.board_id)
    : null;

  const statusColorMap = {
    planned: "bg-blue-500",
    in_progress: "bg-yellow-500",
    completed: "bg-green-500",
    cancelled: "bg-red-500",
  };

  const priorityColorMap = {
    low: "bg-gray-500",
    medium: "bg-yellow-500",
    high: "bg-orange-500",
    urgent: "bg-red-500",
  };

  function getStatusColor(status: string) {
    let defaultColor = "bg-gray-800";
    const mappedColor = statusColorMap[status as keyof typeof statusColorMap];
    if (mappedColor) {
      defaultColor = mappedColor;
    }
    return defaultColor;
  }

  function getPriorityColor(priority: string) {
    let defaultColor = "bg-gray-800";
    const mappedColor =
      priorityColorMap[priority as keyof typeof priorityColorMap];
    if (mappedColor) {
      defaultColor = mappedColor;
    }
    return defaultColor;
  }

  return (
    <div className="w-64 flex-shrink-0 space-y-4 hidden md:block">
      <Card>
        <CardHeader>
          <FeedbackAvatarServer feedback={feedback} />
        </CardHeader>
        <CardContent className="space-y-4">
          {userRoleType === "admin" ? (
            <BoardSelectionDialog
              feedbackId={feedbackId}
              currentBoardId={feedback.board_id}
              boards={boards || []}
            />
          ) : (
            board && (
              <div className="flex items-center gap-2">
                <Layout className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm capitalize">
                  Board: <Badge variant="outline">{board.title}</Badge>
                </span>
              </div>
            )
          )}

          <div className="flex items-center gap-2">
            <ListTodo className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm capitalize">
              Status:{" "}
              <Badge className={getStatusColor(feedback.status)}>
                {feedback.status}
              </Badge>
            </span>
          </div>

          <div className="flex items-center gap-2">
            <Type className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm capitalize">
              Type: <Badge variant="outline">{feedback.type}</Badge>
            </span>
          </div>

          <div className="flex items-center gap-2">
            <Flag className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm capitalize">
              Priority:{" "}
              <Badge className={getPriorityColor(feedback.priority)}>
                {feedback.priority}
              </Badge>
            </span>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Recent Feedback</CardTitle>
        </CardHeader>
        <CardContent>
          <Suspense fallback={<RecentFeedbackSkeleton />}>
            <RecentPublicFeedback />
          </Suspense>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm flex gap-1 items-center">
            <Info className="h-4 w-4" />
            Community Guidelines
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            Please remember that this is a public forum. We kindly ask all users
            to conduct themselves in a civil and respectful manner. Let&apos;s
            foster a positive environment for everyone.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
