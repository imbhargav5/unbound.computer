import { AdminBreadcrumb } from "@/components/app-admin/admin-breadcrumb";
import { ADMIN_BREADCRUMBS } from "@/components/app-admin/breadcrumb-config";

export default function InvoicesNavbar() {
  return (
    <AdminBreadcrumb segments={ADMIN_BREADCRUMBS["payment-gateway/invoices"]} />
  );
}
