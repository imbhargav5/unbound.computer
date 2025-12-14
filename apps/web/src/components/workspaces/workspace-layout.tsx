import { type ReactNode, Suspense } from "react";
import { InternalNavbar } from "@/components/navigation-menu/internal-navbar";
import {
  getCachedSoloWorkspace,
  getCachedWorkspaceBySlug,
} from "@/rsc-data/user/workspaces";
import { SidebarProviderWithState } from "../sidebar-provider-with-state";
import { SidebarInset } from "../ui/sidebar";

async function WorkspaceTestIds({
  workspaceSlug,
}: {
  workspaceSlug: string | undefined;
}) {
  const workspace = workspaceSlug
    ? await getCachedWorkspaceBySlug(workspaceSlug)
    : await getCachedSoloWorkspace();

  return (
    <div
      aria-hidden="true"
      className="hidden"
      data-testid="workspace-details"
      data-workspace-id={workspace.id}
      data-workspace-membership-type={workspace.membershipType}
      data-workspace-name={workspace.name}
      data-workspace-slug={workspace.slug}
    />
  );
}

export async function WorkspaceLayout({
  children,
  navbar,
  sidebar,
  workspaceSlug,
}: {
  children: ReactNode;
  navbar: ReactNode;
  sidebar: ReactNode;
  // undefined for solo workspace
  workspaceSlug: string | undefined;
}) {
  return (
    <SidebarProviderWithState>
      {sidebar}
      <SidebarInset
        className="overflow-hidden"
        style={{
          maxHeight: "calc(100svh - 16px)",
        }}
      >
        <div className="overflow-y-auto">
          <div>
            <Suspense fallback={null}>
              <WorkspaceTestIds workspaceSlug={workspaceSlug} />
            </Suspense>
            <InternalNavbar>
              <div className="w-full items-center justify-between lg:flex">
                <Suspense>{navbar}</Suspense>
              </div>
            </InternalNavbar>
            <div className="relative h-auto w-full flex-1 overflow-auto">
              <div className="space-y-6 px-6 py-6">{children}</div>
            </div>
          </div>
        </div>
      </SidebarInset>
    </SidebarProviderWithState>
  );
}
