import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import {
  getActiveSessionCount,
  getSessionHistory,
} from "@/data/user/coding-sessions";
import {
  getRepositoryCount,
  getUserRepositories,
} from "@/data/user/repositories";
import { RepositoriesList } from "./repositories-list";
import { SessionsList } from "./sessions-list";

export const metadata = {
  title: "Dashboard",
  description: "View your coding sessions and repositories",
};

async function ActiveSessionsSection() {
  const allSessions = await getSessionHistory(50);
  const sessions = allSessions.filter((s) => s.status === "active");

  return (
    <section>
      <h2 className="mb-4 font-semibold text-xl">Active Sessions</h2>
      <SessionsList sessions={sessions} />
    </section>
  );
}

async function RepositoriesSection() {
  const repositories = await getUserRepositories();

  return (
    <section>
      <h2 className="mb-4 font-semibold text-xl">Repositories</h2>
      <RepositoriesList repositories={repositories} />
    </section>
  );
}

async function SessionHistorySection() {
  const history = await getSessionHistory(10);
  const nonActive = history.filter((s) => s.status !== "active");

  if (nonActive.length === 0) {
    return null;
  }

  return (
    <section>
      <h2 className="mb-4 font-semibold text-xl">Recent Sessions</h2>
      <SessionsList sessions={nonActive} />
    </section>
  );
}

async function DashboardStats() {
  const [activeCount, repoCount] = await Promise.all([
    getActiveSessionCount(),
    getRepositoryCount(),
  ]);

  return (
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
      <div className="rounded-lg border p-4">
        <div className="font-bold text-2xl">{activeCount}</div>
        <div className="text-muted-foreground text-sm">Active Sessions</div>
      </div>
      <div className="rounded-lg border p-4">
        <div className="font-bold text-2xl">{repoCount}</div>
        <div className="text-muted-foreground text-sm">Repositories</div>
      </div>
    </div>
  );
}

function SectionSkeleton() {
  return (
    <div className="space-y-4">
      <Skeleton className="h-6 w-40" />
      <Skeleton className="h-24 w-full" />
      <Skeleton className="h-24 w-full" />
    </div>
  );
}

export default function UserDashboardPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="font-bold text-2xl">Dashboard</h1>
        <p className="text-muted-foreground">
          Monitor your coding sessions and repositories.
        </p>
      </div>

      <Suspense fallback={<Skeleton className="h-20 w-full" />}>
        <DashboardStats />
      </Suspense>

      <Suspense fallback={<SectionSkeleton />}>
        <ActiveSessionsSection />
      </Suspense>

      <Suspense fallback={<SectionSkeleton />}>
        <RepositoriesSection />
      </Suspense>

      <Suspense fallback={<SectionSkeleton />}>
        <SessionHistorySection />
      </Suspense>
    </div>
  );
}
