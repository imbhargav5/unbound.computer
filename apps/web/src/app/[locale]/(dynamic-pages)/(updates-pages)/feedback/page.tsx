import { setRequestLocale } from "next-intl/server";
import { Suspense } from "react";
import { GiveFeedbackAnonUser } from "@/components/give-feedback-anon-use";
import { T } from "@/components/type-system";
import { DropdownMenuItem } from "@/components/ui/dropdown-menu";
import { serverGetUserType } from "@/utils/server/server-get-user-type";
import { userRoles } from "@/utils/user-types";
import { AdminFeedbackList } from "./[feedbackId]/admin-feedback-list";
import { AnonFeedbackList } from "./[feedbackId]/anon-feedback-list";
import { GiveFeedbackDialog } from "./[feedbackId]/give-feedback-dialog";
import { LoggedInUserFeedbackList } from "./[feedbackId]/logged-in-user-feedback-list";
import { filtersSchema } from "./[feedbackId]/schema";
import { CreateBoardDialog } from "./create-board-dialog";
import { FeedbackListSidebar, SidebarSkeleton } from "./feedback-list-sidebar";
import { FeedbackPageHeading } from "./feedback-page-heading";

async function FeedbackPageContent({
  searchParams,
  params,
}: {
  searchParams: Promise<unknown>;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  const validatedSearchParams = filtersSchema.parse(await searchParams);
  const userRoleType = await serverGetUserType();
  const suspenseKey = JSON.stringify(validatedSearchParams);

  const actions = (
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

  return (
    <div className="space-y-6 py-6">
      <FeedbackPageHeading
        actions={actions}
        subTitle="Engage with the community and share your ideas."
        title="Community Feedback"
      />

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
    </div>
  );
}

async function FeedbackPage(props: {
  searchParams: Promise<unknown>;
  params: Promise<{ locale: string }>;
}) {
  return (
    <Suspense fallback={<T.Subtle>Loading feedback...</T.Subtle>}>
      <FeedbackPageContent
        params={props.params}
        searchParams={props.searchParams}
      />
    </Suspense>
  );
}

export default FeedbackPage;
