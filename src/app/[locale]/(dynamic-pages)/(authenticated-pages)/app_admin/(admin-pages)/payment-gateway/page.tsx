import { StripePaymentGateway } from "@/payments/StripePaymentGateway";
import { StripePaymentGatewayAdminPanel } from "./StripePaymentGatewayAdminPanel";

export default async function PaymentsAdminPanel() {
  const stripeGateway = new StripePaymentGateway();
  const products = await stripeGateway.superAdminScope.listAllProducts();
  return <StripePaymentGatewayAdminPanel products={products} />;
}
