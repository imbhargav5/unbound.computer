// components/LoggedInUserFeedbackPage.tsx
import { Pagination } from '@/components/Pagination'
import { Search } from '@/components/Search'
import { H3, P } from "@/components/ui/Typography"
import { Card, CardContent, CardFooter, CardHeader } from "@/components/ui/card"
import { Separator } from '@/components/ui/separator'
import { getLoggedInUserFeedbackList, getLoggedInUserFeedbackTotalPages } from '@/data/user/internalFeedback'
import FeedbackDetailWrapper from './FeedbackDetail'
import { FeedbackFacetedFilters } from './FeedbackFacetedFilters'
import { FeedbackItem } from './FeedbackItem'
import { FeedbackDetailFallback } from './FeedbackPageFallbackUI'
import { FiltersSchema } from './schema'

async function LoggedInUserFeedbackPage({ filters, feedbackId }: { filters: FiltersSchema; feedbackId?: string }) {
  const feedbacks = await getLoggedInUserFeedbackList(filters)
  const totalFeedbackPages: number = await getLoggedInUserFeedbackTotalPages(filters)

  return (
    <div className="h-full w-full flex md:gap-2">
      <Card className={`md:flex flex-col flex-1 h-full max-w-[40rem] ${feedbackId ? 'hidden md:flex' : ''}`}>
        <CardHeader>
          <Search placeholder="Search Feedback... " />
          <FeedbackFacetedFilters />
        </CardHeader>
        <CardContent className="flex-1 overflow-y-auto">
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
            <Card className="flex h-full items-center justify-center">
              <CardContent className="text-center">
                <H3>No feedbacks available</H3>
                <P className="text-muted-foreground">You must be logged in to view feedback.</P>
              </CardContent>
            </Card>
          )}
        </CardContent>
        <CardFooter>
          <Pagination totalPages={totalFeedbackPages} />
        </CardFooter>
      </Card>
      <Separator orientation="vertical" className="hidden md:block" />
      <Card className={`md:block flex-1 relative ${!feedbackId ? 'hidden' : ''}`}>
        {feedbacks.length > 0 ? (
          <FeedbackDetailWrapper feedbackId={feedbackId ?? feedbacks[0]?.id} />
        ) : (
          <FeedbackDetailFallback />
        )}
      </Card>
    </div>
  )
}

export default LoggedInUserFeedbackPage
