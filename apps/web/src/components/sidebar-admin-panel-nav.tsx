import {
  Book,
  CreditCard,
  FileLineChart,
  HelpCircle,
  Map,
  PenTool,
  Settings,
  Users,
} from "lucide-react";
import { Suspense } from "react";
import { Link } from "@/components/intl-link";
import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import { getIsAppAdmin } from "@/data/user/user";

const adminLinks = [
  {
    label: "Admin Dashboard",
    href: "/app-admin",
    icon: <FileLineChart className="h-5 w-5" />,
  },
  {
    label: "Payment Gateways",
    href: "/app-admin/payment-gateway",
    icon: <CreditCard className="h-5 w-5" />,
  },
  {
    label: "Users",
    href: "/app-admin/users",
    icon: <Users className="h-5 w-5" />,
  },
  {
    label: "Application Settings",
    href: "/app-admin/settings",
    icon: <Settings className="h-5 w-5" />,
  },
  {
    label: "Marketing Authors",
    href: "/app-admin/marketing/authors",
    icon: <CreditCard className="h-5 w-5" />,
  },
  {
    label: "Marketing Tags",
    href: "/app-admin/marketing/tags",
    icon: <CreditCard className="h-5 w-5" />,
  },
  {
    label: "Marketing Blog",
    href: "/app-admin/marketing/blog",
    icon: <PenTool className="h-5 w-5" />,
  },
  {
    label: "Marketing Feedback List",
    href: "/feedback",
    icon: <HelpCircle className="h-5 w-5" />,
  },
  {
    label: "Marketing Changelog List",
    href: "/app-admin/marketing/changelog",
    icon: <Book className="h-5 w-5" />,
  },
  {
    label: "Marketing Roadmap",
    href: "/roadmap",
    icon: <Map className="h-5 w-5" />,
  },
];

async function AdminPanelSidebar() {
  const isAdmin = await getIsAppAdmin();
  if (!isAdmin) return null;
  return (
    <SidebarGroup className="group-data-[collapsible=icon]:hidden">
      <SidebarGroupLabel data-testid="admin-panel-label">
        Admin Panel
      </SidebarGroupLabel>
      <SidebarMenu>
        {adminLinks.map((link) => (
          <SidebarMenuItem key={link.href}>
            <Suspense>
              <SidebarMenuButton asChild tooltip={link.label}>
                <Link href={link.href}>
                  {link.icon}
                  <span>{link.label}</span>
                </Link>
              </SidebarMenuButton>
            </Suspense>
          </SidebarMenuItem>
        ))}
      </SidebarMenu>
    </SidebarGroup>
  );
}

export async function SidebarAdminPanelNav() {
  return (
    <Suspense fallback={null}>
      <AdminPanelSidebar />
    </Suspense>
  );
}
