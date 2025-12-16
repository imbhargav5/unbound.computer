import { connection } from "next/server";
import { Suspense } from "react";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import { InvoicesTable } from "./invoices-table";

async function InvoicesPageContent() {
  await connection();
  const stripeGateway = new StripePaymentGateway();
  const invoices =
    await stripeGateway.superAdminScope.listCurrentMonthInvoices();

  return (
    <div className="container mx-auto py-10">
      <h1 className="mb-5 font-bold text-2xl">Invoices</h1>
      <InvoicesTable invoices={invoices} />
    </div>
  );
}

export default async function InvoicesPage() {
  return (
    <Suspense>
      <InvoicesPageContent />
    </Suspense>
  );
}
