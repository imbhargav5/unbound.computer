import { T, Typography } from "@/components/ui/Typography"
import { Badge } from '@/components/ui/badge'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { getAnonUserFeedbackById } from '@/data/anon/marketing-feedback'
import { feedbackPriorityToLabel, feedbackStatusToLabel, feedbackTypeToLabel } from "@/utils/zod-schemas/feedback"
import { format } from 'date-fns'
import { Calendar, EyeIcon, Info } from 'lucide-react'
import { notFound } from "next/navigation"
import { SuspendedFeedbackComments } from './CommentTimeLine'

async function AnonUserFeedbackDetail({ feedbackId }: { feedbackId: string }) {
  const feedback = await getAnonUserFeedbackById(feedbackId)

  if (!feedback) {
    return notFound();
  }

  return (
    <>
      <div className="flex items-center justify-between py-2 px-4 ">
        <div className="flex items-center gap-2">
          <Calendar className="h-4 w-4 text-muted-foreground" />
          <span className="text-muted-foreground text-sm lg:text-base">
            {format(new Date(feedback.created_at), 'do MMMM yyyy')}
          </span>
        </div>
        <div data-testid='feedback-visibility' className='flex items-center gap-2'>
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger>
                <Badge variant="outline" className="px-2 rounded-full flex gap-2 items-center border-green-300 text-green-500">
                  <EyeIcon className="w-4 h-4" /> <span>Public</span> <Info className="w-4 h-4" />
                </Badge>
              </TooltipTrigger>
              <TooltipContent>
                This feedback is visible to the public
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
      </div>
      <div className="p-4">
        <h2 className="text-2xl font-medium my-4">{feedback.title}</h2>
        <T.Subtle className="mb-4">{feedback.content}</T.Subtle>
        <div className="flex gap-4 items-center">
          <Badge variant="outline" className="px-3 py-2 capitalize w-fit">
            Status: {feedbackStatusToLabel(feedback.status)}
          </Badge>
          <Badge variant="outline" className="px-3 py-2 capitalize w-fit">
            Type: {feedbackTypeToLabel(feedback.type)}
          </Badge>
          <Badge variant="outline" className="px-3 py-2 capitalize w-fit">
            Priority: {feedbackPriorityToLabel(feedback.priority)}
          </Badge>
        </div>
      </div>
      <div className="border-t p-4 mt-4 gap-2">
        <Typography.H4 className='!mt-0 mb-4'>Comments</Typography.H4>
        <SuspendedFeedbackComments feedbackId={feedback?.id} />
      </div>
    </>
  )
}

export default AnonUserFeedbackDetail
