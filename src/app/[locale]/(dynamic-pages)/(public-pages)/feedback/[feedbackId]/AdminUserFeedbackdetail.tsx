import { Separator } from '@/components/ui/separator';
import { adminGetInternalFeedbackById } from '@/data/admin/internal-feedback';

import { SuspendedUserAvatarWithFullname } from '@/components/UserAvatarForAnonViewers';
import { Badge } from '@/components/ui/badge';
import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { format } from 'date-fns';
import { Calendar, EyeIcon, EyeOffIcon } from 'lucide-react';
import { AddComment } from './AddComment';
import {
  CommentTimeLineItem,
  SuspendedFeedbackComments,
} from './CommentTimeLine';
import { FeedbackActionsDropdown } from './FeedbackActionsDropdown';

async function AdminUserFeedbackdetail({ feedbackId }) {
  const userRoleType = await serverGetUserType();
  const feedback = await adminGetInternalFeedbackById(feedbackId);

  return (
    <div className="h-full py-2 flex flex-col">
      <div className="p-6">
        <div className="flex items-center justify-between">
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
        <h2 className="text-2xl font-medium my-4">{feedback?.title}</h2>
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
      <Separator orientation="horizontal" />
      <div className="flex-1 px-10 py-10 overflow-y-auto overflow-x-visible shadow-inner">
        <CommentTimeLineItem
          userId={feedback?.user_id}
          comment={feedback?.content}
          postedAt={feedback?.created_at}
        />
        <SuspendedFeedbackComments feedbackId={feedback?.id} />
      </div>
      <div className="border-t p-4">
        <AddComment feedbackId={feedback?.id} />
      </div>
    </div>
  );
}

export default AdminUserFeedbackdetail;
