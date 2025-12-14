// Fix for Next.js parallel routes soft navigation issue
// Without this default.tsx, soft navigation from /app-admin to /app-admin/marketing/* fails
// See: https://github.com/vercel/next.js/issues/58272

import { AdminBreadcrumb } from "@/components/app-admin/admin-breadcrumb";
import { ADMIN_BREADCRUMBS } from "@/components/app-admin/breadcrumb-config";

export default function MarketingDefaultNavbar() {
  return <AdminBreadcrumb segments={ADMIN_BREADCRUMBS.home} />;
}
