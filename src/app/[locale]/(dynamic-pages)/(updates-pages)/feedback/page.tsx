import { PageHeading } from "@/components/PageHeading";
import { GiveFeedbackAnonUser } from "@/components/give-feedback-anon-use";
import { Button } from "@/components/ui/button";
import { serverGetUserType } from "@/utils/server/serverGetUserType";
import { userRoles } from "@/utils/userTypes";
import { Suspense } from "react";
import { CreateBoardDialog } from "./CreateBoardDialog";
import { FeedbackSidebar, SidebarSkeleton } from "./FeedbackSidebar";
import { AdminFeedbackList } from "./[feedbackId]/AdminFeedbackList";
import { AnonFeedbackList } from "./[feedbackId]/AnonFeedbackList";
import { GiveFeedbackDialog } from "./[feedbackId]/GiveFeedbackDialog";
import { LoggedInUserFeedbackList } from "./[feedbackId]/LoggedInUserFeedbackList";
import { filtersSchema } from "./[feedbackId]/schema";

async function FeedbackPage(props: {
  searchParams: Promise<unknown>;
  params: Promise<{ feedbackId: string }>;
}) {
  const searchParams = await props.searchParams;
  const validatedSearchParams = filtersSchema.parse(searchParams);
  const userRoleType = await serverGetUserType();
  const suspenseKey = JSON.stringify(validatedSearchParams);

  const actions = (
    <div className="flex gap-2">
      {userRoleType === userRoles.ADMIN && (
        <CreateBoardDialog>
          <Button variant="outline" size="sm">
            Create Board
          </Button>
        </CreateBoardDialog>
      )}

      {userRoleType === userRoles.ANON ? (
        <GiveFeedbackAnonUser>
          <Button variant="secondary" size="sm">
            Create Feedback
          </Button>
        </GiveFeedbackAnonUser>
      ) : (
        <GiveFeedbackDialog>
          <Button variant="default" size="sm">
            Create Feedback
          </Button>
        </GiveFeedbackDialog>
      )}
    </div>
  );

  return (
    <div className="py-6 space-y-6">
      <PageHeading
        title="Community Feedback"
        subTitle="Engage with the community and share your ideas."
        actions={actions}
      />

      <div className="flex gap-4 w-full">
        <div className="flex-1">
          <Suspense
            key={suspenseKey}
            fallback={
              <div className="flex items-center justify-center h-full">
                <div className="animate-pulse">Loading feedback...</div>
              </div>
            }
          >
            {userRoleType === userRoles.ANON && (
              <AnonFeedbackList filters={validatedSearchParams} />
            )}

            {userRoleType === userRoles.USER && (
              <LoggedInUserFeedbackList filters={validatedSearchParams} />
            )}

            {userRoleType === userRoles.ADMIN && (
              <AdminFeedbackList filters={validatedSearchParams} />
            )}
          </Suspense>
        </div>
        <Suspense fallback={<SidebarSkeleton />}>
          <FeedbackSidebar />
        </Suspense>
      </div>
    </div>
  );
}

export default FeedbackPage;
