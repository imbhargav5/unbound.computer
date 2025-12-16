import { Suspense } from "react";
import { GiveFeedbackAnonUser } from "@/components/give-feedback-anon-use";
import { DropdownMenuItem } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { serverGetClaimType } from "@/utils/server/server-get-user-type";
import { userRoles } from "@/utils/user-types";
import { AdminFeedbackList } from "./[feedbackId]/admin-feedback-list";
import { AnonFeedbackList } from "./[feedbackId]/anon-feedback-list";
import { GiveFeedbackDialog } from "./[feedbackId]/give-feedback-dialog";
import { LoggedInUserFeedbackList } from "./[feedbackId]/logged-in-user-feedback-list";
import { filtersSchema } from "./[feedbackId]/schema";
import { CreateBoardDialog } from "./create-board-dialog";
import { FeedbackListSidebar, SidebarSkeleton } from "./feedback-list-sidebar";
import { FeedbackPageHeading } from "./feedback-page-heading";

async function DynamicFeedbackList({
  searchParams,
}: {
  searchParams: Promise<unknown>;
}) {
  const validatedSearchParams = filtersSchema.parse(await searchParams);
  const userRoleType = await serverGetClaimType();
  const suspenseKey = JSON.stringify(validatedSearchParams);
  return (
    <div className="w-full gap-4 md:flex">
      <div className="flex-1">
        <Suspense
          fallback={
            <div className="flex h-full items-center justify-center">
              <div className="animate-pulse">Loading feedback...</div>
            </div>
          }
          key={suspenseKey}
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
        <FeedbackListSidebar />
      </Suspense>
    </div>
  );
}

async function DynamicFeedbackActions() {
  const userRoleType = await serverGetClaimType();
  return (
    <>
      <DropdownMenuItem asChild>
        {userRoleType === userRoles.ADMIN && (
          <CreateBoardDialog>Create Board</CreateBoardDialog>
        )}
      </DropdownMenuItem>

      {userRoleType === userRoles.ANON ? (
        <DropdownMenuItem asChild>
          <GiveFeedbackAnonUser>Create Feedback</GiveFeedbackAnonUser>
        </DropdownMenuItem>
      ) : (
        <DropdownMenuItem asChild>
          <GiveFeedbackDialog>Create Feedback</GiveFeedbackDialog>
        </DropdownMenuItem>
      )}
    </>
  );
}

async function StaticFeedbackPageContent({
  children,
  dynamicFeedbackActions,
}: {
  children: React.ReactNode;
  dynamicFeedbackActions: React.ReactNode;
}) {
  "use cache";
  return (
    <div className="space-y-6 py-6">
      <FeedbackPageHeading
        actions={dynamicFeedbackActions}
        subTitle="Engage with the community and share your ideas."
        title="Community Feedback"
      />
      {children}
    </div>
  );
}

async function FeedbackPage(props: { searchParams: Promise<unknown> }) {
  return (
    <StaticFeedbackPageContent
      dynamicFeedbackActions={
        <Suspense fallback={<DropdownMenuItem>Loading...</DropdownMenuItem>}>
          <DynamicFeedbackActions />
        </Suspense>
      }
    >
      <Suspense fallback={<Skeleton className="h-[24px] w-full" />}>
        <DynamicFeedbackList searchParams={props.searchParams} />
      </Suspense>
    </StaticFeedbackPageContent>
  );
}

export default FeedbackPage;
