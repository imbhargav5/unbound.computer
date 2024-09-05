import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { Suspense } from 'react';
import AdminUserFeedbackdetail from './AdminUserFeedbackdetail';
import AnonUserFeedbackdetail from './AnonUserFeedbackdetail';
import { FeedbackDetailFallback } from './FeedbackPageFallbackUI';
import LoggedInUserFeedbackdetail from './LoggedInUserFeedbackDetail';

async function FeedbackDetailWrapper({ feedbackId }) {
  const userRoleType = await serverGetUserType();

  return (
    <div className="h-full border sticky top-0 rounded-lg">
      <Suspense fallback={<FeedbackDetailFallback />}>
        {userRoleType === userRoles.ANON && (
          <AnonUserFeedbackdetail feedbackId={feedbackId} />
        )}
        {userRoleType === userRoles.ADMIN && (
          <AdminUserFeedbackdetail feedbackId={feedbackId} />
        )}
        {userRoleType === userRoles.USER && (
          <LoggedInUserFeedbackdetail feedbackId={feedbackId} />
        )}
      </Suspense>
    </div>
  );
}

export default FeedbackDetailWrapper;
