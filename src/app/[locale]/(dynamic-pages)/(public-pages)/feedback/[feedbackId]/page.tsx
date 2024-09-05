import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { Suspense } from 'react';
import AdminUserFeedbackPage from './AdminUserFeedbackPage';
import AnonUserFeedbackPage from './AnonUserFeedbackPage';
import FeedbackPageFallbackUI from './FeedbackPageFallbackUI';
import LoggedInUserFeedbackPage from './LoggedInUserFeedbackPage';
import { filtersSchema } from './schema';

async function FeedbackPage({
  params,
  searchParams,
}: {
  searchParams: unknown;
  params: { feedbackId: string };
}) {
  const validatedSearchParams = filtersSchema.parse(searchParams);
  const userRoleType = await serverGetUserType();
  const suspenseKey = JSON.stringify(validatedSearchParams);

  return (
    <Suspense
      key={JSON.stringify(suspenseKey)}
      fallback={<FeedbackPageFallbackUI feedbackId={params?.feedbackId} />}
    >
      {userRoleType === userRoles.ANON && (
        <AnonUserFeedbackPage
          feedbackId={params?.feedbackId}
          filters={validatedSearchParams}
        />
      )}
      {userRoleType === userRoles.USER && (
        <LoggedInUserFeedbackPage
          feedbackId={params?.feedbackId}
          filters={validatedSearchParams}
        />
      )}
      {userRoleType === userRoles.ADMIN && (
        <AdminUserFeedbackPage
          feedbackId={params?.feedbackId}
          filters={validatedSearchParams}
        />
      )}
    </Suspense>
  );
}

export default FeedbackPage;
