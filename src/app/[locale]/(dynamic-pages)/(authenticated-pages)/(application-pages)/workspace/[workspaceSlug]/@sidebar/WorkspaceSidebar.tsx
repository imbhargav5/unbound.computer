// OrganizationSidebar.tsx (Server Component)
import { DesktopSidebarFallback } from '@/components/SidebarComponents/SidebarFallback';
import { Skeleton } from '@/components/ui/skeleton';
import { fetchSlimWorkspaces, getWorkspaceIdBySlug } from '@/data/user/workspaces';
import { workspaceSlugParamSchema } from '@/utils/zod-schemas/params';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import WorkspaceSidebarClient from './WorkspaceSidebarClient';

export async function WorkspaceSidebar({ params }: { params: unknown }) {
  try {
    const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
    const workspaceId = await getWorkspaceIdBySlug(workspaceSlug);
    const slimWorkspaces = await fetchSlimWorkspaces();
    const workspace = slimWorkspaces.find((workspace) => workspace.id === workspaceId);
    if (!workspace) {
      return notFound();
    }
    return (
      <Suspense fallback={<DesktopSidebarFallback />}>
        <WorkspaceSidebarClient
          workspaceId={workspaceId}
          workspaceSlug={workspaceSlug}
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

