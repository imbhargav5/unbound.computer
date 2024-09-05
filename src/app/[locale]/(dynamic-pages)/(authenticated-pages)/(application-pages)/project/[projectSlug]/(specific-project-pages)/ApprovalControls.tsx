'use server';

import { getSlimProjectById } from '@/data/user/projects';
import {
  getLoggedInUserWorkspaceRole,
  getSlimWorkspaceById,
} from '@/data/user/workspaces';
import { ApprovalControlActions } from './ApprovalControlActions';

async function fetchData(projectId: string) {
  const projectByIdData = await getSlimProjectById(projectId);
  const [workspaceData, workspaceRole] = await Promise.all([
    getSlimWorkspaceById(projectByIdData.workspace_id),
    getLoggedInUserWorkspaceRole(projectByIdData.workspace_id),
  ]);

  return {
    projectByIdData,
    workspaceRole,
    workspaceData,
  };
}

export async function ApprovalControls({ projectId }: { projectId: string }) {
  const data = await fetchData(projectId);
  const isOrganizationManager =
    data.workspaceRole === 'admin' || data.workspaceRole === 'owner';
  const canManage = isOrganizationManager;

  const canOnlyEdit = data.workspaceRole === 'member';

  return (
    <ApprovalControlActions
      projectId={projectId}
      canManage={canManage}
      canOnlyEdit={canOnlyEdit}
      projectStatus={data.projectByIdData.project_status}
    />
  );
}
