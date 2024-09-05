import { SwitcherAndToggle } from '@/components/SidebarComponents/SidebarLogo';
import { SidebarLink } from '@/components/SidebarLink';
import { cn } from '@/utils/cn';
import { Book, Briefcase, FileLineChart, HelpCircle, Home, Map, PenTool, Settings, Users } from 'lucide-react';

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
    label: 'Users',
    href: `/app_admin/users`,
    icon: <Users className="h-5 w-5" />,
  },
  {
    label: 'Organizations',
    href: `/app_admin/organizations`,
    icon: <Briefcase className="h-5 w-5" />,
  },
  {
    label: 'Application Settings',
    href: `/app_admin/settings`,
    icon: <Settings className="h-5 w-5" />,
  },
  {
    label: 'Blog',
    href: `/app_admin/blog`,
    icon: <PenTool className="h-5 w-5" />,
  },
  {
    label: 'Feedback List',
    href: `/feedback`,
    icon: <HelpCircle className="h-5 w-5" />,
  },

  {
    label: 'Changelog List',
    href: `/app_admin/changelog`,
    icon: <Book className="h-5 w-5" />,
  },
  {
    label: 'Roadmap',
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
