// UserSidebar.tsx (Server Component)

import { Fragment, Suspense } from "react";
import { SidebarAdminPanelNav } from "@/components/sidebar-admin-panel-nav";
import { SwitcherAndToggle } from "@/components/sidebar-components/switcher-and-toggle";
import { SidebarFooterUserNav } from "@/components/sidebar-footer-user-nav";
import { SidebarPlatformNav } from "@/components/sidebar-platform-nav";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarRail,
} from "@/components/ui/sidebar";
import { Skeleton } from "@/components/ui/skeleton";

async function DynamicSidebarAdminPanelNav() {
  return (
    <Suspense fallback={<Skeleton className="h-10 w-full" />}>
      <SidebarAdminPanelNav />
    </Suspense>
  );
}

async function UserSidebarContent({
  footerUserNav,
  sidebarAdminPanelNav,
}: {
  footerUserNav: React.ReactNode;
  sidebarAdminPanelNav: React.ReactNode;
}) {
  "use cache";
  return (
    <Sidebar collapsible="icon" variant="inset">
      <SidebarHeader>
        <SwitcherAndToggle />
      </SidebarHeader>
      <SidebarContent>
        <Fragment key="sidebar-admin-panel-nav">
          {sidebarAdminPanelNav}
        </Fragment>
        <Fragment key="sidebar-platform-nav">
          <SidebarPlatformNav />
        </Fragment>
      </SidebarContent>
      <SidebarFooter>{footerUserNav}</SidebarFooter>
      <SidebarRail />
    </Sidebar>
  );
}

export async function UserSidebar() {
  return (
    <UserSidebarContent
      footerUserNav={<SidebarFooterUserNav />}
      sidebarAdminPanelNav={<DynamicSidebarAdminPanelNav />}
    />
  );
}
