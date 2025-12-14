import { type ReactNode, Suspense } from "react";
import { WorkspaceLayout } from "@/components/workspaces/workspace-layout";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";

async function TeamWorkspaceLayoutContent(props: {
  children: ReactNode;
  navbar: ReactNode;
  sidebar: ReactNode;
  params: Promise<unknown>;
}) {
  const params = await props.params;

  const { children, navbar, sidebar } = props;

  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);

  return (
    <WorkspaceLayout
      navbar={navbar}
      sidebar={sidebar}
      workspaceSlug={workspaceSlug}
    >
      {children}
    </WorkspaceLayout>
  );
}

export default async function TeamWorkspaceLayout(props: {
  children: ReactNode;
  navbar: ReactNode;
  sidebar: ReactNode;
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <TeamWorkspaceLayoutContent {...props} />
    </Suspense>
  );
}
