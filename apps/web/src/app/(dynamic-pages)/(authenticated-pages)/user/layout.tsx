import { type ReactNode, Suspense } from "react";
import { InternalNavbar } from "@/components/navigation-menu/internal-navbar";
import { SidebarProviderWithState } from "@/components/sidebar-provider-with-state";
import { SidebarInset } from "@/components/ui/sidebar";

export default async function Layout({
  children,
  navbar,
  sidebar,
}: {
  children: ReactNode;
  navbar: ReactNode;
  sidebar: ReactNode;
}) {
  return (
    <SidebarProviderWithState>
      {sidebar}
      <SidebarInset
        className="overflow-hidden"
        style={{
          maxHeight: "calc(100svh - 16px)",
        }}
      >
        <div className="overflow-y-auto">
          <div>
            <InternalNavbar>
              <div className="hidden w-full items-center justify-between lg:flex">
                <Suspense>{navbar}</Suspense>
              </div>
            </InternalNavbar>
            <div className="relative h-auto w-full flex-1 overflow-auto">
              <div className="space-y-6 px-6 py-6">{children}</div>
            </div>
          </div>
        </div>
      </SidebarInset>
    </SidebarProviderWithState>
  );
}
