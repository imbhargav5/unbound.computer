import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { getDeckSessions } from "@/data/user/deck-sessions";
import { getUserRepositories } from "@/data/user/repositories";
import { DeckView } from "./deck/deck-view";

export const metadata = {
  title: "Dashboard",
  description: "View your coding sessions and repositories",
};

function DeckSkeleton() {
  return (
    <div className="space-y-4">
      <Skeleton className="h-10 w-full" />
      <div className="flex gap-4">
        <Skeleton className="h-96 w-72 shrink-0" />
        <Skeleton className="h-96 w-72 shrink-0" />
        <Skeleton className="h-96 w-72 shrink-0" />
      </div>
    </div>
  );
}

async function DeckContent() {
  const [repositories, sessions] = await Promise.all([
    getUserRepositories(),
    getDeckSessions(),
  ]);

  return <DeckView repositories={repositories} sessions={sessions} />;
}

export default function UserDashboardPage() {
  return (
    <Suspense fallback={<DeckSkeleton />}>
      <DeckContent />
    </Suspense>
  );
}
