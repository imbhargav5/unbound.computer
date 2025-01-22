import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/Typography";
import { Button } from "@/components/ui/button";
import { DBTable } from "@/types";
import { formatDistance } from "date-fns";
import { ArrowLeft } from "lucide-react";
import { FeedbackList } from "../../[feedbackId]/FeedbackList";
import { GiveFeedbackDialog } from "../../[feedbackId]/GiveFeedbackDialog";

interface BoardDetailProps {
    board: DBTable<"marketing_feedback_boards">;
    feedbacks: DBTable<"marketing_feedback_threads">[];
    totalPages: number;
    userType: "admin" | "loggedIn" | "anon";
}

export function BoardDetail({ board, feedbacks, totalPages, userType }: BoardDetailProps) {
    return (
        <div className="space-y-6">
            <Button variant="ghost" asChild className="mb-4">
                <Link href="/feedback/boards">
                    <ArrowLeft className="mr-2 h-4 w-4" />
                    Back to boards
                </Link>
            </Button>

            <div className="space-y-2">
                <h1 className="text-3xl font-bold">{board.title}</h1>
                <p className="text-muted-foreground">{board.description}</p>
                <T.Small className="text-muted-foreground">
                    Created {formatDistance(new Date(board.created_at), new Date(), { addSuffix: true })}
                </T.Small>
            </div>

            <div className="flex justify-between items-center">
                <h2 className="text-xl font-semibold">Feedback Threads</h2>
                {userType !== "anon" && (
                    <GiveFeedbackDialog className="w-fit">
                        <Button variant="default">Create Feedback</Button>
                    </GiveFeedbackDialog>
                )}
            </div>

            <FeedbackList
                feedbacks={feedbacks}
                totalPages={totalPages}
                filters={{}}
                userType={userType}
            />
        </div>
    );
}
