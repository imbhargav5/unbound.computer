import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { getWorkspaceSubPath } from "@/utils/workspaces";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import { redirect } from "next/navigation";

export default async function WorkspacePage({
  params
}: {
  params: unknown
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return redirect(getWorkspaceSubPath(workspace, "/home"));
}
