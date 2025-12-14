import { ArrowLeftCircle } from "lucide-react";
import Link from "next/link";
import { Suspense } from "react";
import { GiveFeedbackAnonUser } from "@/components/give-feedback-anon-use";
import { DropdownMenuItem } from "@/components/ui/dropdown-menu";
import type { DBTable } from "@/types";
import { FeedbackList } from "../../[feedbackId]/feedback-list";
import { GiveFeedbackDialog } from "../../[feedbackId]/give-feedback-dialog";
import {
  FeedbackListSidebar,
  SidebarSkeleton,
} from "../../feedback-list-sidebar";
import { FeedbackPageHeading } from "../../feedback-page-heading";

interface BoardDetailProps {
  board: DBTable<"marketing_feedback_boards">;
  feedbacks: (DBTable<"marketing_feedback_threads"> & {
    comment_count: number;
    reaction_count: number;
  })[];
  totalPages: number;
  userType: "admin" | "loggedIn" | "anon";
}

export function BoardDetail({
  board,
  feedbacks,
  totalPages,
  userType,
}: BoardDetailProps) {
  const actions = (
    <DropdownMenuItem asChild>
      {userType === "anon" ? (
        <GiveFeedbackAnonUser>Create Feedback</GiveFeedbackAnonUser>
      ) : (
        <GiveFeedbackDialog>Create Feedback</GiveFeedbackDialog>
      )}
    </DropdownMenuItem>
  );

  return (
    <div className="space-y-6">
      <div className="flex w-full items-start gap-2">
        <Link href="/feedback">
          <ArrowLeftCircle className="h-8 w-8" />
        </Link>
        <FeedbackPageHeading
          actions={actions}
          className="w-full"
          subTitle={board.description ?? "No description"}
          title={board.title}
        />
      </div>

      <div className="flex w-full gap-4">
        <div className="flex-1">
          <FeedbackList
            feedbacks={feedbacks}
            filters={{}}
            totalPages={totalPages}
            userType={userType}
          />
        </div>
        <Suspense fallback={<SidebarSkeleton />}>
          <FeedbackListSidebar />
        </Suspense>
      </div>
    </div>
  );
}
