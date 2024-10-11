// OrganizationSidebar.tsx (Server Component)
import { DesktopSidebarFallback } from "@/components/SidebarComponents/SidebarFallback";
import { Skeleton } from "@/components/ui/skeleton";
import {
  getCachedSlimWorkspaces,
  getCachedSoloWorkspace,
} from "@/rsc-data/user/workspaces";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import SoloWorkspaceSidebarClient from "./SoloWorkspaceSidebarClient";

export async function SoloWorkspaceSidebar() {
  try {
    const [workspace, slimWorkspaces] = await Promise.all([
      getCachedSoloWorkspace(),
      getCachedSlimWorkspaces(),
    ]);
    return (
      <Suspense fallback={<DesktopSidebarFallback />}>
        <SoloWorkspaceSidebarClient
          workspaceId={workspace.id}
          workspaceSlug={workspace.slug}
          workspace={workspace}
          slimWorkspaces={slimWorkspaces}
          subscription={
            <Suspense fallback={<Skeleton className="h-2 w-full" />}>
              <div>
                {/* <SubscriptionCardSmall organizationSlug={organizationSlug} organizationId={organizationId} /> */}
              </div>
            </Suspense>
          }
        />
      </Suspense>
    );
  } catch (e) {
    return notFound();
  }
}
