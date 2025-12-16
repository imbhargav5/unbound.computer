import { connection } from "next/server";
import { Suspense } from "react";
import { Typography } from "@/components/ui/typography-ui";
import { DataAndReports } from "./data-and-reports";
import { QuickMetrics } from "./quick-metrics";
import { RevenueCharts } from "./revenue-charts";
import { StripeProductManager } from "./stripe-product-manager";

async function PaymentsAdminPanelContent() {
  await connection();
  return (
    <div className="container mx-auto p-6">
      <Typography.H2>Admin Panel</Typography.H2>
      <div className="space-y-6">
        <Suspense fallback={<div>Loading...</div>}>
          <StripeProductManager />
        </Suspense>
        <Suspense fallback={<div>Loading...</div>}>
          <QuickMetrics />
        </Suspense>
        <Suspense fallback={<div>Loading...</div>}>
          <DataAndReports />
        </Suspense>
        <Suspense fallback={<div>Loading...</div>}>
          <RevenueCharts />
        </Suspense>
      </div>
    </div>
  );
}

export default async function PaymentsAdminPanel() {
  return (
    <Suspense>
      <PaymentsAdminPanelContent />
    </Suspense>
  );
}
