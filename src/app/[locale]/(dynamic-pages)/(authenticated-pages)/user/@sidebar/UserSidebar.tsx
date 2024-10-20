"use client";

import { Link } from "@/components/intl-link";
import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import { Code, FileQuestion, Home, Mail, Settings, Shield } from "lucide-react";

const sidebarLinks = [
  {
    label: "Dashboard",
    href: "/dashboard",
    icon: <Home className="h-5 w-5" />,
  },
  {
    label: "Account Settings",
    href: "/user/settings",
    icon: <Settings className="h-5 w-5" />,
  },
  {
    label: "Security Settings",
    href: "/user/settings/security",
    icon: <Shield className="h-5 w-5" />,
  },
  {
    label: "Developer Settings",
    href: "/user/settings/developer",
    icon: <Code className="h-5 w-5" />,
  },
  {
    label: "Invitations",
    href: "/user/invitations",
    icon: <Mail className="h-5 w-5" />,
  },
  {
    label: "My Feedback",
    href: "/feedback",
    icon: <FileQuestion className="h-5 w-5" />,
  },
];

export function UserSidebar() {
  return (
    <SidebarGroup>
      <SidebarGroupLabel>User</SidebarGroupLabel>
      <SidebarMenu>
        {sidebarLinks.map((link) => (
          <SidebarMenuItem key={link.href}>
            <SidebarMenuButton asChild>
              <Link href={link.href}>
                {link.icon}
                {link.label}
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        ))}
      </SidebarMenu>
    </SidebarGroup>
  );
}
