// components/AdminUserFeedbackDetail.tsx
import { H2, Small } from "@/components/ui/Typography"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardFooter, CardHeader } from "@/components/ui/card"
import { Separator } from '@/components/ui/separator'
import { adminGetInternalFeedbackById } from '@/data/admin/internal-feedback'
import { serverGetUserType } from '@/utils/server/serverGetUserType'
import { format } from 'date-fns'
import { Calendar, EyeIcon, EyeOffIcon } from 'lucide-react'
import { AddComment } from './AddComment';
import { CommentTimeLineItem, SuspendedFeedbackComments } from './CommentTimeLine'
import { FeedbackActionsDropdown } from './FeedbackActionsDropdown'


async function AdminUserFeedbackDetail({ feedbackId }: { feedbackId: string }) {
  const userRoleType = await serverGetUserType()
  const feedback = await adminGetInternalFeedbackById(feedbackId)

  return (
    <Card className="h-full flex flex-col">
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex flex-col lg:flex-row lg:items-center gap-2">
            <Avatar className="h-8 w-8">
              <AvatarImage src={`https://avatar.vercel.sh/${feedback.user_id}`} alt="User avatar" />
              <AvatarFallback>U</AvatarFallback>
            </Avatar>
            <Separator className='h-6 hidden lg:block' orientation='vertical' />
            <div className='flex gap-2 items-center ml-2'>
              <Calendar className="h-4 w-4 text-muted-foreground" />
              <Small className="text-muted-foreground">
                {format(new Date(feedback.created_at), 'do MMMM yyyy')}
              </Small>
            </div>
          </div>
          <div className='flex items-center gap-2'>
            <Badge variant={feedback.is_publicly_visible ? "secondary" : "outline"} className="flex items-center gap-2">
              {feedback.is_publicly_visible ? <EyeIcon className="w-4 h-4" /> : <EyeOffIcon className="w-4 h-4" />}
              <span>{feedback.is_publicly_visible ? 'Public' : 'Hidden'}</span>
            </Badge>
            <FeedbackActionsDropdown feedback={feedback} userRole={userRoleType} />
          </div>
        </div>
        <H2 className="mt-4">{feedback.title}</H2>
        <div className="flex gap-4 items-center">
          <Badge variant="secondary" className="capitalize">Status: {feedback.status}</Badge>
          <Badge variant="secondary" className="capitalize">Type: {feedback.type}</Badge>
          <Badge variant="secondary" className="capitalize">Priority: {feedback.priority}</Badge>
        </div>
      </CardHeader>
      <Separator />
      <CardContent className="flex-1 overflow-y-auto">
        <CommentTimeLineItem
          userId={feedback.user_id}
          comment={feedback.content}
          postedAt={feedback.created_at}
        />
        <SuspendedFeedbackComments feedbackId={feedback.id} />
      </CardContent>
      <CardFooter>
        <AddComment feedbackId={feedback.id} />
      </CardFooter>
    </Card>
  )
}

export default AdminUserFeedbackDetail
