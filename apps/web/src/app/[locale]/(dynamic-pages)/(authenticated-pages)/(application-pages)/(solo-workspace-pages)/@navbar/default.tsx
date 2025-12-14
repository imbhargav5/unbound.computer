// https://github.com/vercel/next.js/issues/58272

import { WORKSPACE_BREADCRUMBS } from "@/components/workspaces/breadcrumb-config";
import { WorkspaceBreadcrumb } from "@/components/workspaces/workspace-breadcrumb";

export default function DefaultNavbar() {
  return (
    <WorkspaceBreadcrumb basePath="" segments={WORKSPACE_BREADCRUMBS.home} />
  );
}
