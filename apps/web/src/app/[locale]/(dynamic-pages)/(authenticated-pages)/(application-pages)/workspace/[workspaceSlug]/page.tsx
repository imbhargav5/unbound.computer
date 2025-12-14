import { redirect } from "@/i18n/navigation";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { getWorkspaceSubPath } from "@/utils/workspaces";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

export default async function WorkspacePage(props: {
  params: Promise<{ locale: string }>;
}) {
  const params = await props.params;
  const { locale } = params;
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  const path = getWorkspaceSubPath(workspace, "/home");
  redirect({ href: path, locale });
}
