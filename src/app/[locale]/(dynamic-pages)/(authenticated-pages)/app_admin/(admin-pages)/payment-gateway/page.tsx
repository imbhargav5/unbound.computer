import { StripePaymentGateway } from "@/payments/StripePaymentGateway";
import { StripePaymentGatewayAdminPanel } from "./StripePaymentGatewayAdminPanel";

export default async function PaymentsAdminPanel() {
  const stripeGateway = new StripePaymentGateway();
  const plans = await stripeGateway.superAdminScope.listAllPlans();
  return <StripePaymentGatewayAdminPanel plans={plans} />;
}
