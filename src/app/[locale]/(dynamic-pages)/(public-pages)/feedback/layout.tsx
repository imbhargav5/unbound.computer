import { PageHeading } from '@/components/PageHeading';
import { GiveFeedbackAnonUser } from '@/components/give-feedback-anon-use';
import { Button } from '@/components/ui/button';
import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { GiveFeedbackDialog } from './[feedbackId]/GiveFeedbackDialog';

async function FeedbackLayout({ children }) {
  const userRoleType = await serverGetUserType();
  return (
    <section className="w-full h-screen max-h-screen px-4 py-6 ">
      <main className="max-w-[1296px] h-full max-h-[calc(100%-3rem)] mx-auto flex flex-col">
        <div className="flex justify-between items-center">
          <PageHeading
            title="Explore Feedback"
            subTitle="Browse the collection of feedback from your users."
          />

          {
            userRoleType === userRoles.ANON ? (
              <GiveFeedbackAnonUser className='w-fit'>
                <Button variant="secondary">Create Feedback</Button>
              </GiveFeedbackAnonUser>
            ) : (
              <GiveFeedbackDialog className='w-fit'>
                <Button variant="secondary">Create Feedback</Button>
              </GiveFeedbackDialog>
            )
          }

        </div>

        <div className="mt-4 w-full h-full max-h-[88vh]">{children}</div>
      </main>
    </section >
  );
}

export default FeedbackLayout;
