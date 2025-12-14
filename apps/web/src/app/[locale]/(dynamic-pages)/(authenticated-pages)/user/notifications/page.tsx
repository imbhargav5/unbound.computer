import { connection } from "next/server";
import { Suspense } from "react";
import { Separator } from "@/components/ui/separator";
import { T } from "@/components/ui/typography-ui";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import { NotificationPageContent } from "./notification-page-content";

export const metadata = {
  title: "Notifications",
  description: "View and manage your notifications",
};

async function NotificationsPageContent() {
  await connection();
  const userClaims = await serverGetLoggedInUserClaims();
  return (
    <div className="container max-w-5xl space-y-8 py-8">
      <div className="space-y-2">
        <T.H2>Notifications</T.H2>
        <T.P className="text-muted-foreground">
          Stay updated with all your activities and updates
        </T.P>
      </div>
      <Separator />
      <NotificationPageContent userClaims={userClaims} />
    </div>
  );
}

export default async function NotificationsPage() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <NotificationsPageContent />
    </Suspense>
  );
}
