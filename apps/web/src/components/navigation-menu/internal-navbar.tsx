import { type ReactNode, Suspense } from "react";
import { cn } from "@/utils/cn";
import { PendingInvitationCounter } from "./pending-invitation-counter";

async function StaticContent({
  children,
  pendingInvitationCounter,
}: {
  children: ReactNode;
  pendingInvitationCounter: ReactNode;
}) {
  "use cache";
  return (
    <header className="sticky top-0 z-10 h-[64px] w-full bg-background backdrop-blur-sm">
      <div
        className={cn(
          "mx-auto flex h-full w-full items-center justify-between gap-2 border-b py-3 pr-6 pl-6 font-medium text-sm dark:border-gray-700/50"
        )}
      >
        {children}
        <div className="relative flex w-max items-center gap-2">
          <div className="hidden items-center gap-2 lg:flex">
            <div className="flex items-center gap-2">
              {pendingInvitationCounter}
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}

export function InternalNavbar({ children }: { children: ReactNode }) {
  return (
    <StaticContent
      pendingInvitationCounter={
        <Suspense>
          <PendingInvitationCounter />
        </Suspense>
      }
    >
      {children}
    </StaticContent>
  );
}
