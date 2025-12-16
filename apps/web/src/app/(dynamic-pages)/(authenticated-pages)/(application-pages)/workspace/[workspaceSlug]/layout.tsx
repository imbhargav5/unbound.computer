import { type ReactNode, Suspense } from "react";
import { InternalNavbar } from "@/components/navigation-menu/internal-navbar";
import { SidebarProviderWithState } from "@/components/sidebar-provider-with-state";
import { SidebarInset } from "@/components/ui/sidebar";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

async function DynamicWorkspaceTestIds({
  params,
}: {
  params: Promise<unknown>;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(await params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

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

async function StaticTeamWorkspaceLayoutContent(props: {
  children: ReactNode;
  navbar: ReactNode;
  sidebar: ReactNode;
  params: Promise<unknown>;
}) {
  const { children, navbar, sidebar } = props;

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
              <DynamicWorkspaceTestIds params={props.params} />
            </Suspense>
            <InternalNavbar>
              <div className="w-full items-center justify-between lg:flex">
                {navbar}
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

export default async function TeamWorkspaceLayout(props: {
  children: ReactNode;
  navbar: ReactNode;
  sidebar: ReactNode;
  params: Promise<unknown>;
}) {
  return <StaticTeamWorkspaceLayoutContent {...props} />;
}
