import type { BreadcrumbSegment } from "@/components/workspaces/breadcrumb-config";

export const PROJECT_BREADCRUMBS: Record<string, BreadcrumbSegment[]> = {
  home: [],
  settings: [{ label: "Settings" }],
};
