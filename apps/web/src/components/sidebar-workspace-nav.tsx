import {
  DollarSign,
  FileBox,
  Home,
  Layers,
  Settings,
  Users,
} from "lucide-react";
import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import type { SlimWorkspace } from "@/types";
import { getWorkspaceSubPath } from "@/utils/workspaces";
import { Link } from "./intl-link";
import { ProFeatureGateDialog } from "./pro-feature-gate-dialog";

export function SidebarWorkspaceNav({
  workspace,
  withLinkLabelPrefix = false,
}: {
  workspace: SlimWorkspace;
  withLinkLabelPrefix?: boolean;
}) {
  let sidebarLinks = [
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
    const lastItem = sidebarLinks.pop();
    sidebarLinks.push({
      label: "Members",
      href: "/settings/members",
      icon: <Users className="h-5 w-5" />,
    });
    if (lastItem) {
      sidebarLinks.push(lastItem);
    }
  }

  if (withLinkLabelPrefix) {
    sidebarLinks = sidebarLinks.map((link) => ({
      ...link,
      label: `Workspace ${link.label}`,
    }));
  }

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
            icon={<FileBox className="h-5 w-5" />}
            label="Feature Pro"
            workspace={workspace}
          />
        </SidebarMenuItem>
      </SidebarMenu>
    </SidebarGroup>
  );
}
