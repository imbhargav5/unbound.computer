import { NotepadText } from "lucide-react";
import { Suspense } from "react";
import { Link } from "@/components/intl-link";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getFeedbackBoardColorClass } from "@/constants";
import {
  getFeedbackBoardsWithCounts,
  getTotalFeedbackCount,
} from "@/data/admin/marketing-feedback";
import { cn } from "@/utils/cn";
import { FeedbackFilterDialog } from "./components/feedback-filter-dialog";

export function SidebarSkeleton() {
  return (
    <div className="w-64 shrink-0 p-4">
      <Skeleton className="mb-6 h-10 w-full" />
      <div className="space-y-4">
        <Skeleton className="h-4 w-20" />
        <div className="space-y-2">
          {[...Array(5)].map((_, i) => (
            <Skeleton className="h-8 w-full" key={i} />
          ))}
        </div>
      </div>
    </div>
  );
}

export async function FeedbackListSidebar() {
  const boards = await getFeedbackBoardsWithCounts();
  const totalCount = await getTotalFeedbackCount();

  return (
    <div className="hidden w-64 shrink-0 space-y-4 md:block">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-1 text-sm">
            <NotepadText className="h-4 w-4" />
            Boards
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <Link className="flex items-center justify-between" href="/feedback">
            <div className="flex items-center gap-2">
              <div
                className={cn(
                  "h-2 w-2 rounded-full",
                  getFeedbackBoardColorClass(null)
                )}
              />
              <span className="text-sm">All Feedback</span>
            </div>
            <Badge variant="secondary">{totalCount}</Badge>
          </Link>
          {boards.map((board) => (
            <Link
              className="flex items-center justify-between"
              href={`/feedback/boards/${board.slug}`}
              key={board.id}
            >
              <div className="flex items-center gap-2">
                <div
                  className={cn(
                    "h-2 w-2 rounded-full",
                    getFeedbackBoardColorClass(board.color)
                  )}
                />
                <span className="truncate text-sm">{board.title}</span>
              </div>
              <Badge variant="secondary">{board.threadCount}</Badge>
            </Link>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          <Suspense>
            <FeedbackFilterDialog />
          </Suspense>
        </CardContent>
      </Card>

      <div className="text-center">
        <p className="text-muted-foreground text-xs">
          Powered by{" "}
          <a
            className="hover:underline"
            href="https://usenextbase.com"
            rel="noopener noreferrer"
            target="_blank"
          >
            Nextbase
          </a>
        </p>
      </div>
    </div>
  );
}
