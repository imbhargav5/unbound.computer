import { unauthorized } from "next/navigation";
import { type ReactNode, Suspense } from "react";
import { NotificationsDialog } from "@/components/notifications-dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";
import PosthogIdentify from "./posthog-identify";

async function DynamicContent() {
  let userClaims: UserClaimsSchemaType | null = null;
  try {
    userClaims = await serverGetLoggedInUserClaims();
  } catch (fetchDataError) {
    unauthorized();
  }

  if (!userClaims) {
    unauthorized();
  }

  return (
    <>
      <Suspense>
        <NotificationsDialog userClaims={userClaims} />
      </Suspense>
      <Suspense>
        <PosthogIdentify userClaims={userClaims} />
      </Suspense>
    </>
  );
}

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <>
      {children}
      <Suspense fallback={<Skeleton className="h-[24px] w-[48px]" />}>
        <DynamicContent />
      </Suspense>
    </>
  );
}
