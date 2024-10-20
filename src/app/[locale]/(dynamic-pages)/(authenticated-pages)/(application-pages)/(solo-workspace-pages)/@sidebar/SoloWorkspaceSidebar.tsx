// OrganizationSidebar.tsx (Server Component)

import { Link } from "@/components/intl-link";
import { ProFeatureGateDialog } from "@/components/ProFeatureGateDialog";
import { SidebarAdminPanelNav } from "@/components/sidebar-admin-panel-nav";
import { SidebarFooterUserNav } from "@/components/sidebar-footer-user-nav";
import { SidebarPlatformNav } from "@/components/sidebar-platform-nav";
import { SidebarTipsNav } from "@/components/sidebar-tips-nav";
import { SwitcherAndToggle } from "@/components/SidebarComponents/SwitcherAndToggle";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarRail,
} from "@/components/ui/sidebar";
import {
  getCachedSlimWorkspaces,
  getCachedSoloWorkspace,
} from "@/rsc-data/user/workspaces";
import { getWorkspaceSubPath } from "@/utils/workspaces";
import { DollarSign, FileBox, Home, Layers, Settings } from "lucide-react";
import { notFound } from "next/navigation";

const sidebarLinks = [
  { label: "Home", href: "/home", icon: <Home className="h-5 w-5" /> },
  {
    label: "Settings",
    href: "/settings",
    icon: <Settings className="h-5 w-5" />,
  },
  {
    label: "Projects",
    href: "/projects",
    icon: <Layers className="h-5 w-5" />,
  },
  {
    label: "Billing",
    href: "/settings/billing",
    icon: <DollarSign className="h-5 w-5" />,
  },
];

export async function SoloWorkspaceSidebar() {
  try {
    const [workspace, slimWorkspaces] = await Promise.all([
      getCachedSoloWorkspace(),
      getCachedSlimWorkspaces(),
    ]);
    return (
      <Sidebar variant="inset" collapsible="icon">
        <SidebarHeader>
          <SwitcherAndToggle
            workspaceId={workspace.id}
            slimWorkspaces={slimWorkspaces}
          />
        </SidebarHeader>
        <SidebarContent>
          <SidebarGroup>
            <SidebarGroupLabel>Workspace</SidebarGroupLabel>
            <SidebarMenu>
              {sidebarLinks.map((link) => (
                <SidebarMenuItem key={link.href}>
                  <SidebarMenuButton asChild>
                    <Link href={getWorkspaceSubPath(workspace, link.href)}>
                      {link.icon}
                      {link.label}
                    </Link>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
              <SidebarMenuItem>
                <ProFeatureGateDialog
                  workspace={workspace}
                  label="Feature Pro"
                  icon={<FileBox className="h-5 w-5" />}
                />
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroup>
          <SidebarAdminPanelNav />
          <SidebarPlatformNav />
          <SidebarTipsNav workspace={workspace} />
        </SidebarContent>
        <SidebarFooter>
          <SidebarFooterUserNav />
        </SidebarFooter>
        <SidebarRail />
      </Sidebar>
    );
  } catch (e) {
    return notFound();
  }
}
