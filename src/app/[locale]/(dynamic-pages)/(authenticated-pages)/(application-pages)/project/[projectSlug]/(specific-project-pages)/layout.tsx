import { ApplicationLayoutShell } from '@/components/ApplicationLayoutShell';
import { InternalNavbar } from '@/components/NavigationMenu/InternalNavbar';
import { PageHeading } from '@/components/PageHeading';
import { getProjectTitleById, getSlimProjectBySlug } from '@/data/user/projects';
import { projectSlugParamSchema } from '@/utils/zod-schemas/params';
import { Suspense, type ReactNode } from 'react';
import { ApprovalControls } from './ApprovalControls';


async function ProjectPageHeading({ projectId }: { projectId: string }) {
  const projectTitle = await getProjectTitleById(projectId);
  return (
    <PageHeading
      title={projectTitle}
      actions={
        <Suspense>
          <ApprovalControls projectId={projectId} />
        </Suspense>
      }
    />
  );
}

export default async function ProjectLayout({
  params,
  children,
  navbar,
  sidebar,
}: {
  children: ReactNode;
  params: unknown;
  navbar: ReactNode;
  sidebar: ReactNode;
}) {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);

  return (
    <ApplicationLayoutShell sidebar={sidebar}>
      <div className="">
        <InternalNavbar>
          <div className="flex w-full justify-between items-center">
            <Suspense>{navbar}</Suspense>
          </div>
        </InternalNavbar>
        <div className="space-y-8 m-6">
          <div className="space-y-0">
            <Suspense>
              <ProjectPageHeading projectId={project.id} />
            </Suspense>
          </div>
          {children}
        </div>
      </div>
    </ApplicationLayoutShell>
  );
}
