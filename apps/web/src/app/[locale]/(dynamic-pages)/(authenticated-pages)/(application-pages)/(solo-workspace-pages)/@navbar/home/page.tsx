import { WORKSPACE_BREADCRUMBS } from "@/components/workspaces/breadcrumb-config";
import { WorkspaceBreadcrumb } from "@/components/workspaces/workspace-breadcrumb";

export default function HomeNavbar() {
  return (
    <WorkspaceBreadcrumb basePath="" segments={WORKSPACE_BREADCRUMBS.home} />
  );
}
