import { unauthorized } from "next/navigation";
import { connection } from "next/server";
import { type ReactNode, Suspense } from "react";
import { CreateWorkspaceDialog } from "@/components/create-workspace-dialog";
import { NotificationsDialog } from "@/components/notifications-dialog";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";
import PosthogIdentify from "./posthog-identify";

async function DynamicContent() {
  await connection();
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
      <Suspense>
        <CreateWorkspaceDialog />
      </Suspense>
    </>
  );
}

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <>
      {children}
      <Suspense>
        <DynamicContent />
      </Suspense>
    </>
  );
}
