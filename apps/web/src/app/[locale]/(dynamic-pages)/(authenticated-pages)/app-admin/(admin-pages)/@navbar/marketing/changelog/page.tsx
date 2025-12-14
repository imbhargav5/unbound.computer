import { AdminBreadcrumb } from "@/components/app-admin/admin-breadcrumb";
import { ADMIN_BREADCRUMBS } from "@/components/app-admin/breadcrumb-config";

export default function ChangelogNavbar() {
  return (
    <AdminBreadcrumb segments={ADMIN_BREADCRUMBS["marketing/changelog"]} />
  );
}
