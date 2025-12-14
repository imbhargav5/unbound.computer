import { cache as reactCache } from "react";
import { getAnonUserFeedbackList } from "@/data/anon/marketing-feedback";
import { FeedbackList } from "./feedback-list";
import type { FiltersSchema } from "./schema";

interface AnonFeedbackListProps {
  filters: FiltersSchema;
}

const cachedGetAnonUserFeedbackList = reactCache(getAnonUserFeedbackList);

export async function AnonFeedbackList({ filters }: AnonFeedbackListProps) {
  const { data: feedbacks, count: totalFeedbackPages } =
    await cachedGetAnonUserFeedbackList(filters);

  return (
    <FeedbackList
      feedbacks={feedbacks}
      filters={filters}
      totalPages={totalFeedbackPages}
      userType="anon"
    />
  );
}
