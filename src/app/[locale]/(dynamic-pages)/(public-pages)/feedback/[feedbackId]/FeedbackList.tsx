import { Pagination } from "@/components/Pagination";
import { Search } from "@/components/Search";
import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/Typography";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { DBTable } from "@/types";
import { formatDistance } from "date-fns";
import { Bug, LucideCloudLightning, MessageSquareDot } from "lucide-react";
import { Suspense } from "react";
import { FeedbackFacetedFilters } from "./FeedbackFacetedFilters";
import type { FiltersSchema } from "./schema";

const typeIcons = {
  bug: <Bug className="h-3 w-3 mr-1 text-destructive" />,
  feature_request: (
    <LucideCloudLightning className="h-3 w-3 mr-1 text-primary" />
  ),
  general: <MessageSquareDot className="h-3 w-3 mr-1 text-secondary" />,
};

const TAGS = {
  bug: "Bug",
  feature_request: "Feature Request",
  general: "General",
};

interface FeedbackItemProps {
  feedback: DBTable<"marketing_feedback_threads">;
  filters: FiltersSchema;
}

function FeedbackItem({ feedback, filters }: FeedbackItemProps) {
  const searchParams = new URLSearchParams();
  if (filters.page) searchParams.append("page", filters.page.toString());
  const href = `/feedback/${feedback.id}?${searchParams.toString()}`;

  return (
    <Link href={href}>
      <Card className="hover:bg-muted/50 transition-colors duration-200">
        <CardHeader className="flex flex-row items-center justify-between space-y-0 py-3">
          <div className="flex items-center space-x-3">
            <Avatar className="h-8 w-8">
              <AvatarImage
                src={`https://avatar.vercel.sh/${feedback.user_id}`}
                alt="User avatar"
              />
              <AvatarFallback>U</AvatarFallback>
            </Avatar>
            <div className="space-y-1">
              <T.Small className="font-medium line-clamp-1">
                {feedback.title}
              </T.Small>
              <T.Small className="text-muted-foreground line-clamp-1">
                {feedback.content}
              </T.Small>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Badge
              variant="secondary"
              className="rounded-full text-xs py-0 px-2"
            >
              {typeIcons[feedback.type]} {TAGS[feedback.type]}
            </Badge>
            <T.Small className="text-muted-foreground whitespace-nowrap">
              {formatDistance(new Date(feedback.created_at), new Date(), {
                addSuffix: true,
              })}
            </T.Small>
          </div>
        </CardHeader>
      </Card>
    </Link>
  );
}

interface FeedbackListProps {
  feedbacks: DBTable<"marketing_feedback_threads">[];
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
    <div className="flex flex-col h-full">
      <div className="p-4 border-b space-y-3">
        <Search placeholder="Search Feedback..." className="max-w-md" />
        <FeedbackFacetedFilters />
      </div>

      <div className="flex-1 overflow-auto p-4 space-y-2">
        {feedbacks.length > 0 ? (
          feedbacks.map((feedback) => (
            <FeedbackItem
              key={feedback.id}
              feedback={feedback}
              filters={filters}
            />
          ))
        ) : (
          <div className="flex h-full w-full items-center justify-center rounded-lg border border-dashed p-8">
            <div className="flex flex-col items-center gap-2 text-center">
              <MessageSquare className="h-8 w-8 text-muted-foreground" />
              <h3 className="font-semibold">No Feedbacks Available</h3>
              <p className="text-sm text-muted-foreground">
                {emptyStateMessages[userType]}
              </p>
            </div>
          </div>
        )}
      </div>

      <div className="border-t p-4">
        <Pagination totalPages={totalPages} />
      </div>
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
