import { TabsNavigation } from '@/components/TabsNavigation';
import { getOrganizationIdBySlug } from '@/data/user/organizations';
import { organizationSlugParamSchema } from '@/utils/zod-schemas/params';
import { DollarSign, SquarePen, UsersRound } from 'lucide-react';

export default async function OrganizationSettingsLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: unknown;
}) {
  const { organizationSlug } = organizationSlugParamSchema.parse(params);
  const organizationId = await getOrganizationIdBySlug(organizationSlug)
  const tabs = [
    {
      label: 'General',
      href: `/${organizationSlug}/settings`,
      icon: <SquarePen />,
    },
    {
      label: 'Organization Members',
      href: `/${organizationSlug}/settings/members`,
      icon: <UsersRound />,
    },
    {
      label: 'Billing',
      href: `/${organizationSlug}/settings/billing`,
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
