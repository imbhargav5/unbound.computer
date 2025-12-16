export type WorkspaceBreadcrumbSubPathSegment = {
  label: string;
  subPath?: string; // If undefined = current page (no link)
};

export const WORKSPACE_BREADCRUMBS: Record<
  string,
  WorkspaceBreadcrumbSubPathSegment[]
> = {
  home: [],
  projects: [{ label: "Projects" }],
  settings: [{ label: "Settings" }],
  "settings/billing": [
    { label: "Settings", subPath: "/settings" },
    { label: "Billing" },
  ],
  "settings/members": [
    { label: "Settings", subPath: "/settings" },
    { label: "Members" },
  ],
};
