export type BreadcrumbSegment = {
  label: string;
  href?: string; // If undefined = current page (no link)
};

export const ADMIN_BREADCRUMBS: Record<string, BreadcrumbSegment[]> = {
  // Dashboard
  home: [],

  // Users
  users: [{ label: "Users" }],
  "users/[userId]": [
    { label: "Users", href: "/users" },
    { label: "User Details" },
  ],

  // Workspaces
  workspaces: [{ label: "Workspaces" }],
  "workspaces/[workspaceId]": [
    { label: "Workspaces", href: "/workspaces" },
    { label: "Workspace Details" },
  ],

  // Settings
  settings: [{ label: "Settings" }],

  // Payment Gateway
  "payment-gateway": [{ label: "Payment Gateway" }],
  "payment-gateway/customers": [
    { label: "Payment Gateway", href: "/payment-gateway" },
    { label: "Customers" },
  ],
  "payment-gateway/invoices": [
    { label: "Payment Gateway", href: "/payment-gateway" },
    { label: "Invoices" },
  ],
  "payment-gateway/subscriptions": [
    { label: "Payment Gateway", href: "/payment-gateway" },
    { label: "Subscriptions" },
  ],

  // Marketing - Authors
  "marketing/authors": [{ label: "Marketing" }, { label: "Authors" }],
  "marketing/authors/create": [
    { label: "Marketing" },
    { label: "Authors", href: "/marketing/authors" },
    { label: "Create Author" },
  ],
  "marketing/authors/[authorId]": [
    { label: "Marketing" },
    { label: "Authors", href: "/marketing/authors" },
    { label: "Author Details" },
  ],

  // Marketing - Blog
  "marketing/blog": [{ label: "Marketing" }, { label: "Blog" }],
  "marketing/blog/create": [
    { label: "Marketing" },
    { label: "Blog", href: "/marketing/blog" },
    { label: "Create Post" },
  ],
  "marketing/blog/[postId]": [
    { label: "Marketing" },
    { label: "Blog", href: "/marketing/blog" },
    { label: "Edit Post" },
  ],

  // Marketing - Changelog
  "marketing/changelog": [{ label: "Marketing" }, { label: "Changelog" }],
  "marketing/changelog/[changelogId]": [
    { label: "Marketing" },
    { label: "Changelog", href: "/marketing/changelog" },
    { label: "Edit Changelog" },
  ],

  // Marketing - Tags
  "marketing/tags": [{ label: "Marketing" }, { label: "Tags" }],
  "marketing/tags/create": [
    { label: "Marketing" },
    { label: "Tags", href: "/marketing/tags" },
    { label: "Create Tag" },
  ],
  "marketing/tags/[tag_id]": [
    { label: "Marketing" },
    { label: "Tags", href: "/marketing/tags" },
    { label: "Edit Tag" },
  ],
};
