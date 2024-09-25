// OrganizationSidebar.tsx (Server Component)
import { DesktopSidebarFallback } from '@/components/SidebarComponents/SidebarFallback';
import { Skeleton } from '@/components/ui/skeleton';
import { fetchSlimWorkspaces } from '@/data/user/workspaces';
import { getCachedSoloWorkspace } from '@/rsc-data/user/workspaces';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import WorkspaceSidebarClient from './WorkspaceSidebarClient';

export async function WorkspaceSidebar() {
  try {
    const workspace = await getCachedSoloWorkspace();
    const slimWorkspaces = await fetchSlimWorkspaces();
    return (
      <Suspense fallback={<DesktopSidebarFallback />}>
        <WorkspaceSidebarClient
          workspaceId={workspace.id}
          workspaceSlug={workspace.slug}
          workspace={workspace}
          slimWorkspaces={slimWorkspaces}
          subscription={<Suspense fallback={<Skeleton className="h-2 w-full" />}>
            <div>
              {/* <SubscriptionCardSmall organizationSlug={organizationSlug} organizationId={organizationId} /> */}
            </div>
          </Suspense>}
        />
      </Suspense>
    );
  } catch (e) {
    return notFound();
  }
}

