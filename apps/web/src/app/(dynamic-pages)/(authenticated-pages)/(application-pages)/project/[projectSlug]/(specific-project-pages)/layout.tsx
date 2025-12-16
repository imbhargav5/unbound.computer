import { type ReactNode, Suspense } from "react";
import { InternalNavbar } from "@/components/navigation-menu/internal-navbar";
import { PageHeading } from "@/components/page-heading";
import { SidebarProviderWithState } from "@/components/sidebar-provider-with-state";
import { SidebarInset } from "@/components/ui/sidebar";
import { getCachedProjectBySlug } from "@/rsc-data/user/projects";
import { projectSlugParamSchema } from "@/utils/zod-schemas/params";
import { ApprovalControls } from "./approval-controls";
import { ProjectCommentsSheet } from "./project-comments-sheet";

async function ProjectPageHeading({
  projectSlug,
  title,
}: {
  projectSlug: string;
  title: string;
}) {
  const project = await getCachedProjectBySlug(projectSlug);
  return (
    <PageHeading
      actions={
        <Suspense>
          <div className="flex space-x-4">
            <ApprovalControls projectSlug={projectSlug} />
            <ProjectCommentsSheet
              projectId={project.id}
              projectSlug={projectSlug}
            />
          </div>
        </Suspense>
      }
      title={title}
    />
  );
}

async function ProjectLayoutContent({
  params,
  navbar,
  sidebar,
  children,
}: {
  params: Promise<unknown>;
  navbar: ReactNode;
  sidebar: ReactNode;
  children: ReactNode;
}) {
  const { projectSlug } = projectSlugParamSchema.parse(await params);
  const project = await getCachedProjectBySlug(projectSlug);

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
            <InternalNavbar>
              <div className="flex w-full items-center justify-between">
                {navbar}
              </div>
            </InternalNavbar>
            <div className="space-y-6 px-6 py-6">
              <div className="space-y-0">
                <Suspense>
                  <ProjectPageHeading
                    projectSlug={projectSlug}
                    title={project.name}
                  />
                </Suspense>
              </div>
              {children}
            </div>
          </div>
        </div>
      </SidebarInset>
    </SidebarProviderWithState>
  );
}

export default async function ProjectLayout(props: {
  children: ReactNode;
  params: Promise<unknown>;
  navbar: ReactNode;
  sidebar: ReactNode;
}) {
  return (
    <Suspense>
      <ProjectLayoutContent {...props} />
    </Suspense>
  );
}
