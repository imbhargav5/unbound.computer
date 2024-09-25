import { SwitcherAndToggle } from '@/components/SidebarComponents/SidebarLogo';
import { SidebarLink } from '@/components/SidebarLink';
import { cn } from '@/utils/cn';
import { Book, Briefcase, CreditCard, FileLineChart, HelpCircle, Home, Map, PenTool, Settings, Users } from 'lucide-react';
const links = [
  {
    label: 'Home',
    href: `/dashboard`,
    icon: <Home className="h-5 w-5" />,
  },
  {
    label: 'Admin Dashboard',
    href: `/app_admin`,
    icon: <FileLineChart className="h-5 w-5" />,
  },
  {
    label: 'Payment Gateways',
    href: `/app_admin/payment-gateway`,
    icon: <CreditCard className="h-5 w-5" />,
  },
  {
    label: 'Users',
    href: `/app_admin/users`,
    icon: <Users className="h-5 w-5" />,
  },
  {
    label: 'Workspaces',
    href: `/app_admin/workspaces`,
    icon: <Briefcase className="h-5 w-5" />,
  },

  {
    label: 'Application Settings',
    href: `/app_admin/settings`,
    icon: <Settings className="h-5 w-5" />,
  },
  {
    label: 'Marketing Authors',
    href: `/app_admin/marketing/authors`,
    icon: <CreditCard className="h-5 w-5" />,
  },
  {
    label: 'Marketing Tags',
    href: `/app_admin/marketing/tags`,
    icon: <CreditCard className="h-5 w-5" />,
  },
  {
    label: 'Marketing Blog',
    href: `/app_admin/marketing/blog`,
    icon: <PenTool className="h-5 w-5" />,
  },
  {
    label: 'Marketing Feedback List',
    href: `/feedback`,
    icon: <HelpCircle className="h-5 w-5" />,
  },

  {
    label: 'Marketing Changelog List',
    href: `/app_admin/marketing/changelog`,
    icon: <Book className="h-5 w-5" />,
  },
  {
    label: 'Marketing Roadmap',
    href: "/roadmap",
    icon: <Map className="h-5 w-5" />,
  },
];

export function ApplicationAdminSidebar() {
  return (
    <div
      className={cn(
        'flex flex-col justify-between h-full',
        'lg:px-3 lg:py-4 lg:pt-2.5 ',
      )}
    >
      <SwitcherAndToggle />
      <div className="h-full">
        {links.map((link) => {
          return (
            <SidebarLink
              key={link.href}
              label={link.label}
              href={link.href}
              icon={link.icon}
            />
          );
        })}
      </div>
    </div>
  );
}
