"use client";

import { ShoppingBag } from "lucide-react";
import { SubscriptionSelect } from "@/components/subscription-select";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { T } from "@/components/ui/typography-ui";
import type { ProductAndPrice } from "@/payments/abstract-payment-gateway";
import { normalizePriceAndCurrency } from "@/utils/currency";
import { formatGatewayPrice } from "@/utils/format-gateway-price";

interface OneTimeProductsClientProps {
  products: ProductAndPrice[];
  workspaceId: string;
}

export function OneTimeProductsClient({
  products,
  workspaceId,
}: OneTimeProductsClientProps) {
  if (products.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <ShoppingBag className="h-6 w-6 text-primary" />
            One-Time Purchases
          </CardTitle>
        </CardHeader>
        <CardContent>
          <T.Subtle>No one-time purchase products found</T.Subtle>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <ShoppingBag className="h-6 w-6 text-primary" />
          One-Time Purchases
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
          {products.map((p) => {
            const price = p.price;
            return (
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
                  <SubscriptionSelect
                    isOneTimePurchase
                    priceId={p.price.gateway_price_id}
                    workspaceId={workspaceId}
                  />
                </CardContent>
              </Card>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}
