import { Activity, CreditCard, DollarSign, Users } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Typography } from "@/components/ui/typography-ui";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";
import { formatCurrency } from "@/utils/currency";

interface MetricCardProps {
  title: string;
  value: string;
  change: string;
  icon: React.ReactNode;
}

function MetricCard({ title, value, change, icon }: MetricCardProps) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="font-medium text-sm">{title}</CardTitle>
        {icon}
      </CardHeader>
      <CardContent>
        <div className="font-bold text-2xl">{value}</div>
        <p className="text-muted-foreground text-xs">{change}</p>
      </CardContent>
    </Card>
  );
}

interface QuickMetricsDisplayProps {
  currentMRR: number;
  mrrIncreasePercentage: number;
  currentSubscriptions: number;
  subscriptionsIncreasePercentage: number;
  currentMonthOneTimePurchaseRevenue: number;
  oneTimePurchaseRevenueIncreasePercentage: number;
  currentMonthRevenue: number;
  revenueIncreasePercentage: number;
}

function QuickMetricsDisplay({
  currentMRR,
  mrrIncreasePercentage,
  currentSubscriptions,
  subscriptionsIncreasePercentage,
  currentMonthOneTimePurchaseRevenue,
  oneTimePurchaseRevenueIncreasePercentage,
  currentMonthRevenue,
  revenueIncreasePercentage,
}: QuickMetricsDisplayProps) {
  return (
    <div className="space-y-4">
      <Typography.H4>Quick Metrics</Typography.H4>
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          change={`+${mrrIncreasePercentage.toFixed(2)}% from last month`}
          icon={<DollarSign className="h-4 w-4 text-muted-foreground" />}
          title="Current MRR"
          value={formatCurrency(currentMRR, "usd")}
        />
        <MetricCard
          change={`+${subscriptionsIncreasePercentage.toFixed(2)}% from last month`}
          icon={<Users className="h-4 w-4 text-muted-foreground" />}
          title="Subscriptions"
          value={currentSubscriptions.toString()}
        />
        <MetricCard
          change={`+${oneTimePurchaseRevenueIncreasePercentage.toFixed(2)}% from last month`}
          icon={<CreditCard className="h-4 w-4 text-muted-foreground" />}
          title="One Time Purchases Revenue"
          value={formatCurrency(currentMonthOneTimePurchaseRevenue, "usd")}
        />
        <MetricCard
          change={`+${revenueIncreasePercentage.toFixed(2)}% from last month`}
          icon={<Activity className="h-4 w-4 text-muted-foreground" />}
          title="Total Revenue"
          value={formatCurrency(currentMonthRevenue, "usd")}
        />
      </div>
    </div>
  );
}

export async function QuickMetrics() {
  const stripeGateway = new StripePaymentGateway();
  const [
    currentMRR,
    lastMonthMRR,
    currentMonthRevenue,
    lastMonthRevenue,
    currentSubscriptions,
    lastMonthSubscriptions,
    currentMonthOneTimePurchaseRevenue,
    lastMonthOneTimePurchaseRevenue,
  ] = await Promise.all([
    stripeGateway.superAdminScope.getCurrentMRR(),
    stripeGateway.superAdminScope.getLastMonthMRR(),
    stripeGateway.superAdminScope.getCurrentMonthRevenue(),
    stripeGateway.superAdminScope.getLastMonthRevenue(),
    stripeGateway.superAdminScope.getCurrentMonthlySubscriptionCount(),
    stripeGateway.superAdminScope.getLastMonthSubscriptionCount(),
    stripeGateway.superAdminScope.getCurrentMonthOneTimePurchaseRevenue(),
    stripeGateway.superAdminScope.getLastMonthOneTimePurchaseRevenue(),
  ]);

  const mrrIncreasePercentage =
    lastMonthMRR > 0
      ? ((currentMRR - lastMonthMRR) / lastMonthMRR) * 100
      : Number.POSITIVE_INFINITY;
  const revenueIncreasePercentage =
    lastMonthRevenue > 0
      ? ((currentMonthRevenue - lastMonthRevenue) / lastMonthRevenue) * 100
      : Number.POSITIVE_INFINITY;
  const subscriptionsIncreasePercentage =
    lastMonthSubscriptions > 0
      ? ((currentSubscriptions - lastMonthSubscriptions) /
          lastMonthSubscriptions) *
        100
      : Number.POSITIVE_INFINITY;
  const oneTimePurchaseRevenueIncreasePercentage =
    lastMonthOneTimePurchaseRevenue > 0
      ? ((currentMonthOneTimePurchaseRevenue -
          lastMonthOneTimePurchaseRevenue) /
          lastMonthOneTimePurchaseRevenue) *
        100
      : Number.POSITIVE_INFINITY;

  return (
    <QuickMetricsDisplay
      currentMonthOneTimePurchaseRevenue={currentMonthOneTimePurchaseRevenue}
      currentMonthRevenue={currentMonthRevenue}
      currentMRR={currentMRR}
      currentSubscriptions={currentSubscriptions}
      mrrIncreasePercentage={mrrIncreasePercentage}
      oneTimePurchaseRevenueIncreasePercentage={
        oneTimePurchaseRevenueIncreasePercentage
      }
      revenueIncreasePercentage={revenueIncreasePercentage}
      subscriptionsIncreasePercentage={subscriptionsIncreasePercentage}
    />
  );
}
