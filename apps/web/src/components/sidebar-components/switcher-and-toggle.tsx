"use client";

import { Home, PanelLeftIcon } from "lucide-react";
import type { SlimWorkspaces } from "@/types";
import { Link } from "../intl-link";
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from "../ui/sidebar";
import { WorkspaceSwitcher } from "./workspace-switcher";

type Props = {
  workspaceId?: string;
  slimWorkspaces?: SlimWorkspaces;
};

function CollapseTrigger() {
  const { toggleSidebar } = useSidebar();
  return (
    <SidebarMenuButton
      className="hidden size-8 md:flex"
      onClick={toggleSidebar}
      size="sm"
      variant="outline"
    >
      <PanelLeftIcon className="size-4" />
    </SidebarMenuButton>
  );
}

export function SwitcherAndToggle({ workspaceId, slimWorkspaces }: Props) {
  const { state, isMobile, toggleSidebar } = useSidebar();

  // On mobile, always show expanded view (workspace switcher)
  // On desktop, show collapsed view only when state is "collapsed"
  if (state === "collapsed" && !isMobile) {
    return (
      <SidebarMenu>
        <SidebarMenuItem>
          <SidebarMenuButton
            data-testid="sidebar-toggle-trigger"
            onClick={toggleSidebar}
            size="lg"
          >
            <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
              <PanelLeftIcon className="size-4" />
            </div>
          </SidebarMenuButton>
        </SidebarMenuItem>
      </SidebarMenu>
    );
  }

  return (
    <div className="flex items-center gap-2">
      <div className="flex-1">
        {workspaceId && slimWorkspaces ? (
          <WorkspaceSwitcher
            currentWorkspaceId={workspaceId}
            slimWorkspaces={slimWorkspaces}
          />
        ) : (
          <SidebarMenu>
            <SidebarMenuItem>
              <SidebarMenuButton
                asChild
                className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
                size="lg"
              >
                <Link href="/dashboard">
                  <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
                    <Home className="size-4" />
                  </div>
                  <span>Nextbase</span>
                </Link>
              </SidebarMenuButton>
            </SidebarMenuItem>
          </SidebarMenu>
        )}
      </div>
      <CollapseTrigger />
    </div>
  );
}
