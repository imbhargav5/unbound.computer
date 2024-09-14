import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { Suspense } from 'react';
import AdminUserFeedbackdetail from './AdminUserFeedbackdetail';
import AnonUserFeedbackdetail from './AnonUserFeedbackdetail';
import { FeedbackDetailFallback } from './FeedbackPageFallbackUI';
import LoggedInUserFeedbackDetail from './LoggedInUserFeedbackDetail';

async function FeedbackPage({
  params,
}: {
  params: { feedbackId: string };
}) {
  const userRoleType = await serverGetUserType();
  const feedbackId = params.feedbackId;

  return (
    <Suspense fallback={<FeedbackDetailFallback />}>
      {userRoleType === userRoles.ANON && (
        <AnonUserFeedbackdetail feedbackId={feedbackId} />
      )}
      {userRoleType === userRoles.USER && (
        <LoggedInUserFeedbackDetail feedbackId={feedbackId} />
      )}
      {userRoleType === userRoles.ADMIN && (
        <AdminUserFeedbackdetail feedbackId={feedbackId} />
      )}
    </Suspense>
  );
}

export default FeedbackPage;
