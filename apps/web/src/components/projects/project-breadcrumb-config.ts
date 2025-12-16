import type { WorkspaceBreadcrumbSubPathSegment } from "@/components/workspaces/breadcrumb-config";

export const PROJECT_BREADCRUMBS: Record<
  string,
  WorkspaceBreadcrumbSubPathSegment[]
> = {
  home: [],
  settings: [{ label: "Settings" }],
};
