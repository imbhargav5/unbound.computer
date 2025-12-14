"use client";

import { CalendarDays, CreditCard, DollarSign, RefreshCw } from "lucide-react";
import { motion } from "motion/react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { T } from "@/components/ui/typography-ui";
import type { SubscriptionData } from "@/payments/abstract-payment-gateway";
import { formatCurrency, normalizePriceAndCurrency } from "@/utils/currency";

interface SubscriptionCardProps {
  subscription: SubscriptionData;
}

const MotionCard = motion(Card);

export function SubscriptionCard({ subscription }: SubscriptionCardProps) {
  const formatDate = (dateString: string) =>
    new Date(dateString).toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });

  const getStatusBadge = (status: string) => {
    switch (status) {
      case "active":
        return <Badge className="bg-green-500 text-white">Active</Badge>;
      case "canceled":
        return <Badge className="bg-red-500 text-white">Canceled</Badge>;
      case "past_due":
        return <Badge className="bg-yellow-500 text-white">Past Due</Badge>;
      default:
        return <Badge>{status}</Badge>;
    }
  };

  const getSubscriptionMessage = () => {
    switch (subscription.status) {
      case "active":
        return subscription.cancel_at_period_end
          ? "This subscription will be canceled at the end of the current period."
          : "This subscription is active and will automatically renew.";
      case "canceled":
        return "This subscription has been canceled and will not renew.";
      case "past_due":
        return "Payment for this subscription is past due. Please update your payment method to avoid service interruption.";
      case "unpaid":
        return "This subscription is unpaid. Please make a payment to reactivate your service.";
      default:
        return "Subscription status is unknown. Please contact support for more information.";
    }
  };

  const { billing_prices, billing_products } = subscription;
  if (!(billing_prices && billing_products)) {
    throw new Error("Subscription has no prices or products");
  }

  const amount = normalizePriceAndCurrency(
    billing_prices.amount,
    billing_prices.currency
  );
  const currency = billing_prices.currency;

  return (
    <MotionCard
      animate={{ opacity: 1, y: 0 }}
      className="overflow-hidden bg-background"
      initial={{ opacity: 0, y: 20 }}
      transition={{ duration: 0.3 }}
    >
      <CardHeader className="border-b bg-muted/30">
        <CardTitle className="flex items-center justify-between">
          <span className="flex items-center gap-2">
            <CreditCard className="h-5 w-5 text-primary" />
            {billing_products.name || "Subscription"}
          </span>
          {getStatusBadge(subscription.status)}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4 pt-4">
        <T.P className="text-gray-600 text-sm">
          {billing_products.description}
        </T.P>

        <div className="grid grid-cols-2 gap-4">
          <div className="flex items-start gap-2">
            <DollarSign className="mt-1 h-5 w-5 text-gray-500" />
            <div>
              <T.P className="font-semibold">
                {formatCurrency(amount, currency)}
              </T.P>
              <T.Small className="text-gray-500">
                {billing_prices.recurring_interval_count === 1
                  ? `per ${billing_prices.recurring_interval}`
                  : `every ${billing_prices.recurring_interval_count} ${billing_prices.recurring_interval}s`}
              </T.Small>
            </div>
          </div>
          <div className="flex items-start gap-2">
            <RefreshCw className="mt-1 h-5 w-5 text-gray-500" />
            <div>
              <T.P className="font-semibold">Next Billing Date</T.P>
              <T.Small className="text-gray-500">
                {formatDate(subscription.current_period_end)}
              </T.Small>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="flex items-start gap-2">
            <CalendarDays className="mt-1 h-5 w-5 text-gray-500" />
            <div>
              <T.P className="font-semibold">Subscription Start</T.P>
              <T.Small className="text-gray-500">
                {formatDate(subscription.current_period_start)}
              </T.Small>
            </div>
          </div>
          <div className="flex items-start gap-2">
            <CalendarDays className="mt-1 h-5 w-5 text-gray-500" />
            <div>
              <T.P className="font-semibold">
                {subscription.cancel_at_period_end
                  ? "Cancellation Date"
                  : "Next Renewal"}
              </T.P>
              <T.Small className="text-gray-500">
                {formatDate(subscription.current_period_end)}
              </T.Small>
            </div>
          </div>
        </div>

        <T.P className="mt-4 text-gray-600 text-sm italic">
          {getSubscriptionMessage()}
        </T.P>
      </CardContent>
    </MotionCard>
  );
}
