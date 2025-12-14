import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import type { WorkspaceWithMembershipType } from "@/types";
import { SubscriptionProductsClient } from "./subscription-products-client";

export async function SubscriptionProductsServer({
  workspace,
}: {
  workspace: WorkspaceWithMembershipType;
}) {
  const stripePaymentGateway = new StripePaymentGateway();
  const productWithPriceListGroup =
    await stripePaymentGateway.anonScope.listAllSubscriptionProducts();

  return (
    <SubscriptionProductsClient
      monthlyProducts={productWithPriceListGroup["month"] ?? []}
      workspaceId={workspace.id}
      yearlyProducts={productWithPriceListGroup["year"] ?? []}
    />
  );
}
