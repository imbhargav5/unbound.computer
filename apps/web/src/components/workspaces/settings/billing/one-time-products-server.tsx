import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import type { WorkspaceWithMembershipType } from "@/types";
import { OneTimeProductsClient } from "./one-time-products-client";

export async function OneTimeProductsServer({
  workspace,
}: {
  workspace: WorkspaceWithMembershipType;
}) {
  const stripePaymentGateway = new StripePaymentGateway();
  const productWithPriceListGroup =
    await stripePaymentGateway.anonScope.listAllOneTimeProducts();

  return (
    <OneTimeProductsClient
      products={productWithPriceListGroup}
      workspaceId={workspace.id}
    />
  );
}
