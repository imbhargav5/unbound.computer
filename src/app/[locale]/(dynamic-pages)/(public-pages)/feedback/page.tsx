import { PageHeading } from '@/components/PageHeading';
import { GiveFeedbackAnonUser } from '@/components/give-feedback-anon-use';
import { Button } from '@/components/ui/button';
import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { Fragment, Suspense } from 'react';
import { AdminFeedbackList } from './[feedbackId]/AdminFeedbackList';
import { AnonFeedbackList } from './[feedbackId]/AnonFeedbackList';
import { GiveFeedbackDialog } from './[feedbackId]/GiveFeedbackDialog';
import { LoggedInUserFeedbackList } from './[feedbackId]/LoggedInUserFeedbackList';
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
    <Fragment>
      <div className="flex justify-between items-center">
        <PageHeading
          title="Explore Feedback"
          subTitle="Browse the collection of feedback from your users."
        />

        {userRoleType === userRoles.ANON ? (
          <GiveFeedbackAnonUser className='w-fit'>
            <Button variant="secondary">Create Feedback</Button>
          </GiveFeedbackAnonUser>
        ) : (
          <GiveFeedbackDialog className='w-fit'>
            <Button variant="default">Create Feedback</Button>
          </GiveFeedbackDialog>
        )}
      </div>

      <div className="w-full h-full max-h-[88vh]">

        <Suspense key={suspenseKey} fallback={<div>Loading...</div>}>
          {userRoleType === userRoles.ANON && (
            <>
              <AnonFeedbackList
                filters={validatedSearchParams}
              />
            </>
          )}


          {userRoleType === userRoles.USER && (
            <LoggedInUserFeedbackList
              filters={validatedSearchParams}
            />
          )}

          {userRoleType === userRoles.ADMIN && (
            <AdminFeedbackList
              filters={validatedSearchParams}
            />
          )}
        </Suspense>
      </div>
    </Fragment>
  );
}

export default FeedbackPage;
