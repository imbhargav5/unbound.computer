// components/AnonUserFeedbackPage.tsx
import { Pagination } from '@/components/Pagination';
import { Search } from '@/components/Search';
import { Separator } from '@/components/ui/separator';
import {
  getAnonUserFeedbackList,
  getAnonUserFeedbackTotalPages,
} from '@/data/anon/internalFeedback';
import clsx from 'clsx';
import FeedbackDetailWrapper from './FeedbackDetail';
import { FeedbackFacetedFilters } from './FeedbackFacetedFilters';
import { FeedbackItem } from './FeedbackItem';
import { FiltersSchema } from './schema';

interface AnonUserFeedbackPageProps {
  filters: FiltersSchema;
  feedbackId?: string;
}

async function AnonUserFeedbackPage({ filters, feedbackId }: AnonUserFeedbackPageProps) {
  const feedbacks = await getAnonUserFeedbackList(filters);
  const totalFeedbackPages = await getAnonUserFeedbackTotalPages(filters);

  return (
    <div className="h-full w-full flex md:gap-2">
      <div
        className={clsx(
          feedbackId && 'hidden',
          'md:flex flex-col flex-1 h-full w-full max-w-[40rem]',
        )}
      >
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
                feedbackId={feedbackId || feedbacks[0].id}
              />
            ))
          ) : (
            <div className="flex h-full w-full items-center justify-center rounded-lg border border-dashed shadow-sm">
              <div className="flex flex-col items-center gap-1 text-center">
                <h3 className="text-2xl font-bold tracking-tight">
                  No feedbacks available
                </h3>
                <p className="text-sm text-muted-foreground">
                  You must be logged in to view feedback.
                </p>
              </div>
            </div>
          )}
        </div>
        <div className="border-t py-2">
          <Pagination totalPages={totalFeedbackPages} />
        </div>
      </div>
      <Separator orientation="vertical" className="hidden md:block" />
      <div
        className={clsx(!feedbackId && '!hidden', 'md:block flex-1 relative')}
      >
        {feedbacks.length > 0 && (
          <FeedbackDetailWrapper feedbackId={feedbackId ?? feedbacks[0]?.id} />
        )}
      </div>
    </div>
  );
}

export default AnonUserFeedbackPage;
