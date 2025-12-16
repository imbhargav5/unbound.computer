import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { Skeleton } from "@/components/ui/skeleton";
import { PendingInvitationsList } from "./pending-invitations-list";

export default async function DashboardPage() {
  return (
    <div className="space-y-4">
      <PageHeading
        subTitle="Manage pending invitations here."
        title="Pending Invitations"
      />
      <Suspense fallback={<Skeleton className="h-6 w-16" />}>
        <PendingInvitationsList />
      </Suspense>
    </div>
  );
}
