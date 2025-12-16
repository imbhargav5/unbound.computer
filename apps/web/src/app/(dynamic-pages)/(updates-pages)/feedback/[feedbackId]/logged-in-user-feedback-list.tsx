import { getLoggedInUserFeedbackList } from "@/data/user/marketing-feedback";
import { FeedbackList } from "./feedback-list";
import type { FiltersSchema } from "./schema";

interface LoggedInUserFeedbackListProps {
  filters: FiltersSchema;
}

export async function LoggedInUserFeedbackList({
  filters,
}: LoggedInUserFeedbackListProps) {
  const { data: feedbacks, count: totalFeedbackPages } =
    await getLoggedInUserFeedbackList(filters);

  return (
    <FeedbackList
      feedbacks={feedbacks}
      filters={filters}
      totalPages={totalFeedbackPages ?? 0}
      userType="loggedIn"
    />
  );
}
