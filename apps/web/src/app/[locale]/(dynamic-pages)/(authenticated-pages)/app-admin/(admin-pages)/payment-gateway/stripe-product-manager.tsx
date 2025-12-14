import { Typography } from "@/components/ui/typography-ui";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import { StripeProductCard } from "./stripe-product-card";

export async function StripeProductManager() {
  const stripeGateway = new StripePaymentGateway();
  const products = await stripeGateway.superAdminScope.listAllProducts();

  return (
    <div className="space-y-4">
      <Typography.H4>Stripe Product Manager</Typography.H4>
      <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
        {products.map((product) => (
          <StripeProductCard
            key={product.gateway_product_id}
            product={product}
          />
        ))}
      </div>
    </div>
  );
}
