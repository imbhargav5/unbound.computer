'use server';

import {
  getLoggedInUserOrganizationRole,
  getSlimOrganizationById,
} from '@/data/user/organizations';
import { getSlimProjectById } from '@/data/user/projects';
import { ApprovalControlActions } from './ApprovalControlActions';

async function fetchData(projectId: string) {
  const projectByIdData = await getSlimProjectById(projectId);
  const [organizationData, organizationRole] = await Promise.all([
    getSlimOrganizationById(projectByIdData.organization_id),
    getLoggedInUserOrganizationRole(projectByIdData.organization_id),
  ]);

  return {
    projectByIdData,
    organizationRole,
    organizationData,
  };
}

export async function ApprovalControls({ projectId }: { projectId: string }) {
  const data = await fetchData(projectId);
  const isOrganizationManager =
    data.organizationRole === 'admin' || data.organizationRole === 'owner';
  const canManage = isOrganizationManager;

  const canOnlyEdit = data.organizationRole === 'member';

  return (
    <ApprovalControlActions
      projectId={projectId}
      canManage={canManage}
      canOnlyEdit={canOnlyEdit}
      projectStatus={data.projectByIdData.project_status}
    />
  );
}
