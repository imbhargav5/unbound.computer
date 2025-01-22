import { Link } from "@/components/intl-link";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { DBTable } from "@/types";
import { formatDistance } from "date-fns";
import { MessageSquare } from "lucide-react";

interface BoardListProps {
  boards: DBTable<"marketing_feedback_boards">[];
  userType: "admin" | "loggedIn" | "anon";
}

export function BoardList({ boards, userType }: BoardListProps) {
  const emptyStateMessages = {
    admin: "No boards created yet. Create one to get started!",
    loggedIn: "No boards available yet.",
    anon: "No public boards found.",
  };

  if (boards.length === 0) {
    return (
      <div className="flex h-full w-full items-center justify-center rounded-lg border border-dashed p-8">
        <div className="flex flex-col items-center gap-2 text-center">
          <MessageSquare className="h-8 w-8 text-muted-foreground" />
          <h3 className="font-semibold">No Boards Available</h3>
          <p className="text-sm text-muted-foreground">
            {emptyStateMessages[userType]}
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
      {boards.map((board) => (
        <Link key={board.id} href={`/feedback/boards/${board.slug}`}>
          <Card className="hover:bg-muted transition-colors">
            <CardHeader>
              <h3 className="text-lg font-semibold">{board.title}</h3>
              <p className="text-sm text-muted-foreground">
                Created{" "}
                {formatDistance(new Date(board.created_at), new Date(), {
                  addSuffix: true,
                })}
              </p>
            </CardHeader>
            <CardContent>
              <p className="text-sm text-muted-foreground line-clamp-2">
                {board.description}
              </p>
            </CardContent>
          </Card>
        </Link>
      ))}
    </div>
  );
}
