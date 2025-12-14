import { PageHeading } from "@/components/page-heading";

export async function WorkspacePageHeading({
  workspaceName,
  workspaceSlug,
}: {
  workspaceName: string;
  workspaceSlug: string;
}) {
  return <PageHeading title={workspaceName} titleHref={`/${workspaceSlug}`} />;
}
