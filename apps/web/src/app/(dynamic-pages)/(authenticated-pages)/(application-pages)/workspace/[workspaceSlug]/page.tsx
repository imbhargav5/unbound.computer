import { redirect } from "next/navigation";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { getWorkspaceSubPath } from "@/utils/workspaces";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

export default async function WorkspacePage(props: {
  params: Promise<{ workspaceSlug: string }>;
}) {
  const params = await props.params;
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  const path = getWorkspaceSubPath(workspace, "/home");
  redirect(path);
}
