import type {
  InvoiceData,
  OneTimePaymentData,
  SubscriptionData,
} from "@/payments/abstract-payment-gateway";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import type { WorkspaceWithMembershipType } from "@/types";
import { CustomerDetailsClient } from "./customer-details-client";

async function getInvoices(workspaceId: string): Promise<InvoiceData[]> {
  const stripePaymentGateway = new StripePaymentGateway();
  const invoices =
    await stripePaymentGateway.userScope.getWorkspaceDatabaseInvoices(
      workspaceId
    );
  return invoices.data;
}

async function getOneTimePurchases(
  workspaceId: string
): Promise<OneTimePaymentData[]> {
  const stripePaymentGateway = new StripePaymentGateway();
  return await stripePaymentGateway.userScope.getWorkspaceDatabaseOneTimePurchases(
    workspaceId
  );
}

async function getSubscriptions(
  workspaceId: string
): Promise<SubscriptionData[]> {
  const stripePaymentGateway = new StripePaymentGateway();
  return await stripePaymentGateway.userScope.getWorkspaceDatabaseSubscriptions(
    workspaceId
  );
}

export async function CustomerDetailsServer({
  workspace,
}: {
  workspace: WorkspaceWithMembershipType;
}) {
  try {
    const stripePaymentGateway = new StripePaymentGateway();
    await stripePaymentGateway.userScope.getWorkspaceDatabaseCustomer(
      workspace.id
    );

    const [invoices, oneTimePurchases, subscriptions] = await Promise.all([
      getInvoices(workspace.id),
      getOneTimePurchases(workspace.id),
      getSubscriptions(workspace.id),
    ]);

    return (
      <CustomerDetailsClient
        invoices={invoices}
        oneTimePurchases={oneTimePurchases}
        subscriptions={subscriptions}
      />
    );
  } catch (error) {
    return null;
  }
}
