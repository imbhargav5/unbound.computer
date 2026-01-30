import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { getUserProfile } from "@/data/user/user";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import { authUserMetadataSchema } from "@/utils/zod-schemas/auth-user-metadata";
import "./onboarding.css";
import { OnboardingProvider } from "./onboarding-context";
import { OnboardingFlowContent } from "./onboarding-flow";

async function OnboardingFlowWrapper() {
  const userClaims = await serverGetLoggedInUserClaims();
  const userProfile = await getUserProfile(userClaims.sub);

  const onboardingStatus = authUserMetadataSchema.parse(
    userClaims.user_metadata
  );

  return (
    <OnboardingProvider
      onboardingStatus={onboardingStatus}
      userEmail={userClaims.email}
      userProfile={userProfile}
    >
      <OnboardingFlowContent />
    </OnboardingProvider>
  );
}

export default async function OnboardingPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-neutral-50 p-6">
          <Skeleton className="h-[600px] w-full max-w-5xl rounded-lg" />
        </div>
      }
    >
      <OnboardingFlowWrapper />
    </Suspense>
  );
}
