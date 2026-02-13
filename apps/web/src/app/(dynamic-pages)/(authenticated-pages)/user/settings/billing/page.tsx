import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import {
  buildUsageStatusPayload,
  ensureStripeBillingCustomer,
  getBillingWindow,
  getUsageCount,
} from "@/app/api/v1/mobile/billing/shared";
import type { ProductAndPrice } from "@/payments/abstract-payment-gateway";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import { formatGatewayPrice } from "@/utils/format-gateway-price";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";
import {
  BillingUsagePanel,
  type BillingUpgradeOption,
  type BillingUsageStatusView,
} from "./billing-usage-panel";

type BillingSettingsModel = {
  usageStatus: BillingUsageStatusView | null;
  upgradeOption: BillingUpgradeOption | null;
  errorMessage: string | null;
};

function selectUpgradeOption(
  subscriptionProducts: ProductAndPrice[]
): BillingUpgradeOption | null {
  const recurringProducts = subscriptionProducts
    .filter(
      ({ price }) =>
        Boolean(price.active) &&
        Boolean(price.recurring_interval) &&
        price.recurring_interval !== "one-time"
    )
    .sort((a, b) => (a.price.amount ?? Number.MAX_SAFE_INTEGER) - (b.price.amount ?? Number.MAX_SAFE_INTEGER));

  const preferred = recurringProducts.find(
    ({ price }) => (price.amount ?? 0) > 0
  );
  const selected = preferred ?? recurringProducts[0];

  if (!selected) {
    return null;
  }

  return {
    priceId: selected.price.gateway_price_id,
    title: selected.product.name,
    label: formatGatewayPrice(selected.price),
  };
}

async function getBillingSettingsModel(): Promise<BillingSettingsModel> {
  const stripePaymentGateway = new StripePaymentGateway();
  const subscriptionProductsByInterval =
    await stripePaymentGateway.anonScope.listAllSubscriptionProducts();
  const subscriptionProducts = Object.values(
    subscriptionProductsByInterval
  ).flat();
  const upgradeOption = selectUpgradeOption(subscriptionProducts);

  try {
    const user = await serverGetLoggedInUserClaims();
    const customer = await ensureStripeBillingCustomer(user.sub);
    const billingWindow = await getBillingWindow(customer.gateway_customer_id);
    const commandsUsed = await getUsageCount({
      gatewayCustomerId: customer.gateway_customer_id,
      usageType: "remote_commands",
      periodStart: billingWindow.periodStart,
      periodEnd: billingWindow.periodEnd,
    });

    const usageStatus = buildUsageStatusPayload({
      plan: billingWindow.plan,
      periodStart: billingWindow.periodStart,
      periodEnd: billingWindow.periodEnd,
      commandsLimit: billingWindow.commandsLimit,
      commandsUsed,
    });

    return {
      usageStatus,
      upgradeOption,
      errorMessage: null,
    };
  } catch (error) {
    return {
      usageStatus: null,
      upgradeOption,
      errorMessage:
        error instanceof Error
          ? error.message
          : "Unable to load billing usage right now.",
    };
  }
}

async function BillingSettingsContent() {
  const model = await getBillingSettingsModel();

  return (
    <div className="max-w-3xl space-y-8">
      <PageHeading
        subTitle="Review your command usage and update billing."
        subTitleClassName="text-base -mt-1"
        title="Billing & Usage"
        titleClassName="text-xl"
      />
      <BillingUsagePanel
        errorMessage={model.errorMessage}
        upgradeOption={model.upgradeOption}
        usageStatus={model.usageStatus}
      />
    </div>
  );
}

export default async function BillingSettingsPage() {
  return (
    <Suspense>
      <BillingSettingsContent />
    </Suspense>
  );
}
