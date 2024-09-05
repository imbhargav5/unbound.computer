import { DesktopSidebarFallback } from '@/components/SidebarComponents/SidebarFallback';
import { fetchSlimOrganizations, getOrganizationSlugByOrganizationId } from '@/data/user/organizations';
import { getSlimProjectById, getSlimProjectBySlug } from '@/data/user/projects';
import { projectSlugParamSchema } from '@/utils/zod-schemas/params';
import { Suspense } from 'react';
import { ProjectSidebarClient } from './ProjectSidebarClient';

export async function ProjectSidebar({ params }: { params: unknown }) {
  const { projectSlug } = projectSlugParamSchema.parse(params);
  const project = await getSlimProjectBySlug(projectSlug);
  const [slimOrganizations, fullProject] = await Promise.all([
    fetchSlimOrganizations(),
    getSlimProjectById(project.id),
  ]);
  const organizationId = fullProject.organization_id;
  const organizationSlug = await getOrganizationSlugByOrganizationId(organizationId);

  return (
    <Suspense fallback={<DesktopSidebarFallback />}>
      <ProjectSidebarClient
        projectId={project.id}
        projectSlug={project.slug}
        organizationId={organizationId}
        organizationSlug={organizationSlug}
        project={fullProject}
        slimOrganizations={slimOrganizations}
      />
    </Suspense>
  );
}
