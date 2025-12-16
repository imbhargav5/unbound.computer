import { connection } from "next/server";
import { Suspense } from "react";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import { SubscriptionsTable } from "./subscriptions-table";

async function SubscriptionsPageContent() {
  await connection();
  const stripeGateway = new StripePaymentGateway();
  const subscriptions =
    await stripeGateway.superAdminScope.listCurrentMonthSubscriptions();

  return (
    <div className="container mx-auto py-10">
      <h1 className="mb-5 font-bold text-2xl">Subscriptions</h1>
      <SubscriptionsTable subscriptions={subscriptions} />
    </div>
  );
}

export default async function SubscriptionsPage() {
  return (
    <Suspense>
      <SubscriptionsPageContent />
    </Suspense>
  );
}
