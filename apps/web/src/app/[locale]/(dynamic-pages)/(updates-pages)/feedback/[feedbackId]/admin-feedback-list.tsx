import { getPaginatedInternalFeedbackList } from "@/data/admin/marketing-feedback";
import { FeedbackList } from "./feedback-list";
import type { FiltersSchema } from "./schema";

interface AdminFeedbackListProps {
  filters: FiltersSchema;
}

export async function AdminFeedbackList({ filters }: AdminFeedbackListProps) {
  const { data: feedbacks, count: totalFeedbackPages } =
    await getPaginatedInternalFeedbackList(filters);

  return (
    <FeedbackList
      feedbacks={feedbacks}
      filters={filters}
      totalPages={totalFeedbackPages ?? 0}
      userType="admin"
    />
  );
}
