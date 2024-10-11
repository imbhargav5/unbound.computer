"use server";

import {
  getLoggedInUserWorkspaceRole,
  getSlimWorkspaceById,
} from "@/data/user/workspaces";
import { getCachedProjectBySlug } from "@/rsc-data/user/projects";
import { ApprovalControlActions } from "./ApprovalControlActions";

async function fetchData(projectSlug: string) {
  const projectByIdData = await getCachedProjectBySlug(projectSlug);
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

export async function ApprovalControls({
  projectSlug,
}: {
  projectSlug: string;
}) {
  const data = await fetchData(projectSlug);
  const isOrganizationManager =
    data.workspaceRole === "admin" || data.workspaceRole === "owner";
  const canManage = isOrganizationManager;

  const canOnlyEdit = data.workspaceRole === "member";
  const projectId = data.projectByIdData.id;
  return (
    <ApprovalControlActions
      projectId={projectId}
      canManage={canManage}
      canOnlyEdit={canOnlyEdit}
      projectStatus={data.projectByIdData.project_status}
    />
  );
}
