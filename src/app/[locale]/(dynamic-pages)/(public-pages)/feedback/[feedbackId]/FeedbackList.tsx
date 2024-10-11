import { Pagination } from "@/components/Pagination";
import { Search } from "@/components/Search";
import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/Typography";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
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
      <Card
        data-testid="feedback-item"
        className="hover:bg-muted transition-colors duration-200 ease-in cursor-pointer group"
      >
        <CardHeader className="flex flex-row items-center justify-between space-y-0 py-2 px-4">
          <div className="flex items-center space-x-2">
            <Avatar className="h-6 w-6">
              <AvatarImage
                src={`https://avatar.vercel.sh/${feedback.user_id}`}
                alt="User avatar"
              />
              <AvatarFallback>U</AvatarFallback>
            </Avatar>
            <T.Small className="font-medium">{feedback.title}</T.Small>
          </div>
          <Badge
            variant="secondary"
            className="rounded-full group-hover:bg-background text-xs py-0 px-2"
          >
            {typeIcons[feedback.type]} {TAGS[feedback.type]}
          </Badge>
        </CardHeader>
        <CardContent className="py-2 px-4">
          <T.Small className="text-muted-foreground line-clamp-1">
            {feedback.content}
          </T.Small>
          <T.Small className="text-muted-foreground mt-1">
            {formatDistance(new Date(feedback.created_at), new Date(), {
              addSuffix: true,
            })}
          </T.Small>
        </CardContent>
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
    <>
      <div className="flex flex-col gap-2 mb-4">
        <Search placeholder="Search Feedback... " />
        <FeedbackFacetedFilters />
      </div>
      <div className="flex flex-col h-full overflow-y-auto gap-2 mb-4">
        {feedbacks.length > 0 ? (
          feedbacks.map((feedback) => (
            <FeedbackItem
              key={feedback.id}
              feedback={feedback}
              filters={filters}
            />
          ))
        ) : (
          <div className="flex h-full w-full items-center justify-center rounded-lg border border-dashed shadow-sm">
            <div className="flex flex-col items-center gap-1 text-center">
              <h3 className="text-2xl font-bold tracking-tight">
                No feedbacks available
              </h3>
              <p className="text-sm text-muted-foreground">
                {emptyStateMessages[userType]}
              </p>
            </div>
          </div>
        )}
      </div>
      <div className="py-8">
        <Pagination totalPages={totalPages} />
      </div>
    </>
  );
}

export function FeedbackList(props: FeedbackListProps) {
  return (
    <Suspense fallback={<div>Loading feedback list...</div>}>
      <FeedbackListContent {...props} />
    </Suspense>
  );
}
