export type BreadcrumbSegment = {
  label: string;
  href?: string; // If undefined = current page (no link)
};

export const WORKSPACE_BREADCRUMBS: Record<string, BreadcrumbSegment[]> = {
  home: [],
  projects: [{ label: "Projects" }],
  settings: [{ label: "Settings" }],
  "settings/billing": [
    { label: "Settings", href: "/settings" },
    { label: "Billing" },
  ],
  "settings/members": [
    { label: "Settings", href: "/settings" },
    { label: "Members" },
  ],
};
