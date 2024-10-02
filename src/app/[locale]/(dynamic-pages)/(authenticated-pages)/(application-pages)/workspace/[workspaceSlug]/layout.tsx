import { WorkspaceLayout } from "@/components/workspaces/WorkspaceLayout";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import type { ReactNode } from "react";

export default function TeamWorkspaceLayout({
  children,
  navbar,
  sidebar,
  params
}: {
  children: ReactNode;
  navbar: ReactNode;
  sidebar: ReactNode;
  params: unknown
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);

  return (
    <WorkspaceLayout workspaceSlug={workspaceSlug} navbar={navbar} sidebar={sidebar}>
      {children}
    </WorkspaceLayout>
  );
}
