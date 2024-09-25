import { StripePaymentGateway } from "@/payments/StripePaymentGateway";
import { StripePaymentGatewayAdminPanel } from "./StripePaymentGatewayAdminPanel";

export default async function PaymentsAdminPanel() {
  const stripeGateway = new StripePaymentGateway();
  const products = await stripeGateway.superAdminScope.listAllProducts();
  const currentMRR = await stripeGateway.superAdminScope.getCurrentMRR();
  const last30DaysRevenue = await stripeGateway.superAdminScope.getLast30DaysRevenue();
  console.log("currentMRR", currentMRR);
  console.log("last30DaysRevenue", last30DaysRevenue);
  return <StripePaymentGatewayAdminPanel products={products} />;
}
