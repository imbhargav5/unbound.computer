// OrganizationSidebar.tsx (Server Component)
import { DesktopSidebarFallback } from '@/components/SidebarComponents/SidebarFallback';
import { SubscriptionCardSmall } from '@/components/SubscriptionCardSmall';
import { Skeleton } from '@/components/ui/skeleton';
import { fetchSlimOrganizations, getOrganizationIdBySlug } from '@/data/user/organizations';
import { organizationSlugParamSchema } from '@/utils/zod-schemas/params';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import OrganizationSidebarClient from './OrganizationSidebarClient';

export async function OrganizationSidebar({ params }: { params: unknown }) {
  try {
    const { organizationSlug } = organizationSlugParamSchema.parse(params);
    const organizationId = await getOrganizationIdBySlug(organizationSlug);
    const slimOrganizations = await fetchSlimOrganizations();

    return (
      <Suspense fallback={<DesktopSidebarFallback />}>
        <OrganizationSidebarClient
          organizationId={organizationId}
          organizationSlug={organizationSlug}
          slimOrganizations={slimOrganizations}
          subscription={<Suspense fallback={<Skeleton className="h-2 w-full" />}>
            <div>
              <SubscriptionCardSmall organizationSlug={organizationSlug} organizationId={organizationId} />
            </div>
          </Suspense>}
        />
      </Suspense>
    );
  } catch (e) {
    return notFound();
  }
}

