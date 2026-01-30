import type { ReactNode } from "react";
import { MobileSidebarTrigger } from "@/components/sidebar-components/mobile-sidebar-trigger";
import { cn } from "@/utils/cn";

async function StaticContent({ children }: { children: ReactNode }) {
  "use cache";
  return (
    <header className="sticky top-0 z-10 h-[64px] w-full bg-background backdrop-blur-sm">
      <div
        className={cn(
          "mx-auto flex h-full w-full items-center justify-between gap-2 border-b py-3 pr-6 pl-6 font-medium text-sm dark:border-gray-700/50"
        )}
      >
        <MobileSidebarTrigger />
        {children}
      </div>
    </header>
  );
}

export function InternalNavbar({ children }: { children: ReactNode }) {
  return <StaticContent>{children}</StaticContent>;
}
