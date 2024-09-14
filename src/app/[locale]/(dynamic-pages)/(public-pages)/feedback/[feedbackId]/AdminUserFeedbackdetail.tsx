import { SuspendedUserAvatarWithFullname } from '@/components/UserAvatarForAnonViewers';
import { T, Typography } from "@/components/ui/Typography";
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { adminGetInternalFeedbackById } from '@/data/admin/marketing-feedback';
import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { format } from 'date-fns';
import { Calendar, EyeIcon, EyeOffIcon } from 'lucide-react';
import { AddComment } from './AddComment';
import { SuspendedFeedbackComments } from './CommentTimeLine';
import { FeedbackActionsDropdown } from './FeedbackActionsDropdown';

async function AdminUserFeedbackdetail({ feedbackId }) {
  const userRoleType = await serverGetUserType();
  const feedback = await adminGetInternalFeedbackById(feedbackId);

  return (
    <>
      <div className="flex items-center justify-between px-4">
        <div className="flex flex-col lg:items-center lg:flex-row gap-2">
          <SuspendedUserAvatarWithFullname
            userId={feedback?.user_id}
            size={32}
          />
          <Separator className='h-6 hidden lg:block' orientation='vertical' />
          <div className='flex gap-2 items-center ml-2'>
            <Calendar className="h-4 w-4 text-muted-foreground" />
            <span className="text-muted-foreground text-sm lg:text-base">
              {format(new Date(feedback?.created_at), 'do MMMM yyyy')}
            </span>
          </div>
        </div>
        <div className='flex items-center gap-2'>
          {feedback.is_publicly_visible ? (
            <Badge variant="outline" className="px-2 rounded-full flex gap-2 items-center border-green-300 text-green-500">
              <EyeIcon className="w-4 h-4" /> <p>Public</p>
            </Badge>
          ) : (
            <Badge variant="outline" className="px-2 rounded-full flex gap-2 items-center">
              <EyeOffIcon className="w-4 h-4" /> <p>Hidden</p>
            </Badge>
          )}
          <FeedbackActionsDropdown
            feedback={feedback}
            userRole={userRoleType}
          />
        </div>
      </div>
      <div className="px-4">
        <h2 className="text-2xl font-medium my-4">{feedback?.title}</h2>
        <T.Subtle className="mb-4">{feedback?.content}</T.Subtle>
        <div className="flex gap-4 items-center">
          <Badge variant="outline" className="px-3 py-2 capitalize w-fit">
            Status: {feedback?.status}
          </Badge>
          <Badge variant="outline" className="px-3 py-2 capitalize w-fit">
            Type: {feedback?.type}
          </Badge>
          <Badge variant="outline" className="px-3 py-2 capitalize w-fit">
            Priority: {feedback?.priority}
          </Badge>
        </div>
      </div>
      <div className="border-t p-4 mt-4 gap-2 flex-1">
        <Typography.H4 className='!mt-0 mb-4'>Comments</Typography.H4>
        <SuspendedFeedbackComments feedbackId={feedback?.id} />
      </div>
      <div className="border-t p-4 mt-4">
        <AddComment feedbackId={feedback?.id} />
      </div>
    </>
  );
}

export default AdminUserFeedbackdetail;
