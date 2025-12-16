import { ArrowLeft } from "lucide-react";
import { connection } from "next/server";
import { Suspense } from "react";
import { z } from "zod";
import { Link } from "@/components/intl-link";
import { serverGetClaimType } from "@/utils/server/server-get-user-type";
import { userRoles } from "@/utils/user-types";
import { AdminFeedbackPageContent } from "./components/user-specific/admin-feedback-page-content";
import { AnonFeedbackPageContent } from "./components/user-specific/anon-feedback-page-content";
import { UserFeedbackPageContent } from "./components/user-specific/user-feedback-page-content";
import { FeedbackDetailSidebar } from "./feedback-detail-sidebar";
import { FeedbackDetailFallback } from "./feedback-page-fallback-ui";

const paramsSchema = z.object({
  feedbackId: z.string(),
});

async function FeedbackContent({
  feedbackId,
  userRoleType,
}: {
  feedbackId: string;
  userRoleType: string;
}) {
  if (userRoleType === userRoles.ANON) {
    return <AnonFeedbackPageContent feedbackId={feedbackId} />;
  }

  if (userRoleType === userRoles.USER) {
    return <UserFeedbackPageContent feedbackId={feedbackId} />;
  }

  if (userRoleType === userRoles.ADMIN) {
    return <AdminFeedbackPageContent feedbackId={feedbackId} />;
  }

  return null;
}

async function FeedbackPageContent({ params }: { params: Promise<unknown> }) {
  await connection();
  const { feedbackId } = paramsSchema.parse(await params);

  // Single user type check for the entire page
  const userRoleType = await serverGetClaimType();
  return (
    <div className="min-h-screen">
      <div className="py-8">
        {/* Back Link */}
        <Link
          className="mb-6 inline-flex items-center gap-2 text-muted-foreground text-sm transition-colors hover:text-foreground"
          href="/feedback"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to all feedback
        </Link>

        {/* Two-Column Layout */}
        <div className="flex flex-col gap-8 lg:flex-row">
          {/* Main Content */}
          <div className="min-w-0 flex-1">
            <Suspense fallback={<FeedbackDetailFallback />}>
              <FeedbackContent
                feedbackId={feedbackId}
                userRoleType={userRoleType}
              />
            </Suspense>
          </div>

          {/* Sidebar */}
          <Suspense
            fallback={
              <div className="w-full lg:w-80">
                <div className="h-64 animate-pulse rounded-lg border bg-card" />
              </div>
            }
          >
            <FeedbackDetailSidebar
              feedbackId={feedbackId}
              userRole={userRoleType}
            />
          </Suspense>
        </div>
      </div>
    </div>
  );
}

export default async function FeedbackPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <FeedbackPageContent params={props.params} />
    </Suspense>
  );
}
