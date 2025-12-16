// https://github.com/vercel/next.js/issues/58272

import { AdminBreadcrumb } from "@/components/app-admin/admin-breadcrumb";
import { ADMIN_BREADCRUMBS } from "@/components/app-admin/breadcrumb-config";

export default function DefaultNavbar() {
  return <AdminBreadcrumb segments={ADMIN_BREADCRUMBS.home} />;
}
