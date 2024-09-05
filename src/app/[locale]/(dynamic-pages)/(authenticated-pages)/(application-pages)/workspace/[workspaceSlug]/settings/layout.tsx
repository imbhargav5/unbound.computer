import { TabsNavigation } from '@/components/TabsNavigation';
import { getCachedWorkspaceBySlug } from '@/rsc-data/user/workspaces';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { workspaceSlugParamSchema } from '@/utils/zod-schemas/params';
import { DollarSign, SquarePen, UsersRound } from 'lucide-react';

export default async function OrganizationSettingsLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug)
  const tabs = [
    {
      label: 'General',
      href: getWorkspaceSubPath(workspace, '/settings'),
      icon: <SquarePen />,
    },
    {
      label: 'Organization Members',
      href: getWorkspaceSubPath(workspace, '/settings/members'),
      icon: <UsersRound />,
    },
    {
      label: 'Billing',
      href: getWorkspaceSubPath(workspace, '/settings/billing'),
      icon: <DollarSign />,
    },
  ];

  return (
    <div className="space-y-6">
      <TabsNavigation tabs={tabs} />
      {children}
    </div>
  );
}
