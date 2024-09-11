import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { Suspense } from 'react';
import AdminUserFeedbackPage from './[feedbackId]/AdminUserFeedbackPage';
import AnonUserFeedbackPage from './[feedbackId]/AnonUserFeedbackPage';
import LoggedInUserFeedbackPage from './[feedbackId]/LoggedInUserFeedbackPage';
import { filtersSchema } from './[feedbackId]/schema';

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
    <Suspense key={suspenseKey} fallback={<div>Loading...</div>}>
      {userRoleType === userRoles.ANON && (
        <>
          <AnonUserFeedbackPage
            feedbackId={params?.feedbackId}
            filters={validatedSearchParams}
          />
        </>
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
