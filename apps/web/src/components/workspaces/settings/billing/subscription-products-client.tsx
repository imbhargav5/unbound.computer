"use client";

import { Package } from "lucide-react";
import { SubscriptionSelect } from "@/components/subscription-select";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { T } from "@/components/ui/typography-ui";
import type { ProductAndPrice } from "@/payments/abstract-payment-gateway";
import { normalizePriceAndCurrency } from "@/utils/currency";
import { formatGatewayPrice } from "@/utils/format-gateway-price";

interface SubscriptionProductsClientProps {
  monthlyProducts: ProductAndPrice[];
  yearlyProducts: ProductAndPrice[];
  workspaceId: string;
}

export function SubscriptionProductsClient({
  monthlyProducts,
  yearlyProducts,
  workspaceId,
}: SubscriptionProductsClientProps) {
  if (monthlyProducts.length === 0 && yearlyProducts.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Package className="h-6 w-6 text-primary" />
            Plans
          </CardTitle>
        </CardHeader>
        <CardContent>
          <T.Subtle>No subscription products found</T.Subtle>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Package className="h-6 w-6 text-primary" />
          Choose Your Plan
        </CardTitle>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="monthly">
          <TabsList className="mb-4">
            <TabsTrigger value="monthly">Monthly Billing</TabsTrigger>
            <TabsTrigger value="yearly">Annual Billing</TabsTrigger>
          </TabsList>
          <TabsContent value="monthly">
            <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
              {monthlyProducts.map((p) => (
                <Card key={p.price.gateway_price_id}>
                  <CardHeader>
                    <CardTitle>{p.product.name}</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <T.P className="mb-4 text-gray-600">
                      {p.product.description}
                    </T.P>
                    <T.H4 className="mb-2 text-primary">
                      {formatGatewayPrice({
                        amount: normalizePriceAndCurrency(
                          p.price.amount,
                          p.price.currency
                        ),
                        currency: p.price.currency,
                        recurring_interval: p.price.recurring_interval,
                        recurring_interval_count:
                          p.price.recurring_interval_count,
                      })}
                    </T.H4>
                    <ul className="mb-4 list-inside list-disc">Features</ul>
                    <SubscriptionSelect
                      priceId={p.price.gateway_price_id}
                      workspaceId={workspaceId}
                    />
                  </CardContent>
                </Card>
              ))}
            </div>
          </TabsContent>
          <TabsContent value="yearly">
            <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
              {yearlyProducts.map((p) => (
                <Card key={p.price.gateway_price_id}>
                  <CardHeader>
                    <CardTitle>{p.product.name}</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <T.P className="mb-4 text-gray-600">
                      {p.product.description}
                    </T.P>
                    <T.H4 className="mb-2 text-primary">
                      {formatGatewayPrice({
                        amount: normalizePriceAndCurrency(
                          p.price.amount,
                          p.price.currency
                        ),
                        currency: p.price.currency,
                        recurring_interval: p.price.recurring_interval,
                        recurring_interval_count:
                          p.price.recurring_interval_count,
                      })}
                    </T.H4>
                    <ul className="mb-4 list-inside list-disc">Features</ul>
                    <SubscriptionSelect
                      priceId={p.price.gateway_price_id}
                      workspaceId={workspaceId}
                    />
                  </CardContent>
                </Card>
              ))}
            </div>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  );
}
