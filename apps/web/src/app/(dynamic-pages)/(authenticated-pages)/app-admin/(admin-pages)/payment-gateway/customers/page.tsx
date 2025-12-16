import { connection } from "next/server";
import { Suspense } from "react";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import { CustomersTable } from "./customers-table";

async function CustomersPageContent() {
  await connection();
  const stripeGateway = new StripePaymentGateway();
  const customers = await stripeGateway.superAdminScope.listCustomers();

  return (
    <div className="container mx-auto py-10">
      <h1 className="mb-5 font-bold text-2xl">Customers</h1>
      <CustomersTable customers={customers} />
    </div>
  );
}

export default async function CustomersPage() {
  return (
    <Suspense>
      <CustomersPageContent />
    </Suspense>
  );
}
