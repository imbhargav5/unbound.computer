"use client";

import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import { SlimWorkspace } from "@/types";
import { getWorkspaceSubPath } from "@/utils/workspaces";
import {
  DollarSign,
  FileBox,
  Home,
  Layers,
  Settings,
  Users,
} from "lucide-react";
import { useMemo } from "react";
import { ProFeatureGateDialog } from "./ProFeatureGateDialog";
import { Link } from "./intl-link";

export function SidebarWorkspaceNav({
  workspace,
}: {
  workspace: SlimWorkspace;
}) {
  const sidebarLinks = useMemo(() => {
    const links = [
      { label: "Home", href: "/home", icon: <Home className="h-5 w-5" /> },

      {
        label: "Projects",
        href: "/projects",
        icon: <Layers className="h-5 w-5" />,
      },
      {
        label: "Settings",
        href: "/settings",
        icon: <Settings className="h-5 w-5" />,
      },
      {
        label: "Billing",
        href: "/settings/billing",
        icon: <DollarSign className="h-5 w-5" />,
      },
    ];

    if (workspace.membershipType === "team") {
      // pop the last item
      const lastItem = links.pop();
      links.push({
        label: "Members",
        href: "/settings/members",
        icon: <Users className="h-5 w-5" />,
      });
      if (lastItem) {
        links.push(lastItem);
      }
    }
    return links;
  }, [workspace]);

  return (
    <SidebarGroup>
      <SidebarGroupLabel>Workspace</SidebarGroupLabel>
      <SidebarMenu>
        {sidebarLinks.map((link) => (
          <SidebarMenuItem key={link.label}>
            <SidebarMenuButton asChild>
              <Link href={getWorkspaceSubPath(workspace, link.href)}>
                {link.icon}
                <span>{link.label}</span>
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
  );
}
