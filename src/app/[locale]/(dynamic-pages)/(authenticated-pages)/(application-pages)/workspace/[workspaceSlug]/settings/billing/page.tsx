import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { T, Typography } from "@/components/ui/Typography";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import { Suspense } from "react";

import { SubscriptionSelect } from "@/components/SubscriptionSelect";
import { InvoiceData, OneTimePaymentData } from '@/payments/AbstractPaymentGateway';
import { StripePaymentGateway } from "@/payments/StripePaymentGateway";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { WorkspaceWithMembershipType } from "@/types";
import { formatGatewayPrice } from "@/utils/formatGatewayPrice";
import type { Metadata } from "next";

async function Subscription({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  const stripePaymentGateway = new StripePaymentGateway();

  try {
    const subscription = await stripePaymentGateway.userScope.getWorkspaceDatabaseSubscriptions(workspace.id);
    console.log('subscription', subscription);
  } catch (error) {
    console.log('no subscription');
    console.error(error);
    return null;
  }
}

export const metadata: Metadata = {
  title: "Billing",
  description: "You can edit your organization's billing details here.",
};

async function SubscriptionProducts({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  const stripePaymentGateway = new StripePaymentGateway();

  const productWithPriceListGroup = await stripePaymentGateway.anonScope.listAllSubscriptionProducts();
  const monthlyProducts = productWithPriceListGroup['month'] ?? [];
  const yearlyProducts = productWithPriceListGroup['year'] ?? [];

  return (
    <div className="space-y-12">
      <div className="space-y-4">
        <Typography.H3>Monthly Subscriptions</Typography.H3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {monthlyProducts.map((p) => {
            return (
              <div key={p.price.gateway_price_id} className="border rounded-lg p-6 shadow-sm">
                <T.H3 className="mb-2">{p.product.name}</T.H3>
                <T.P className="text-gray-600 mb-4">{p.product.description}</T.P>
                <T.H4 className="mb-2">
                  {formatGatewayPrice(p.price)}
                </T.H4>
                <ul className="list-disc list-inside mb-4">
                  Features
                </ul>
                <SubscriptionSelect priceId={p.price.gateway_price_id} workspaceId={workspace.id} />
              </div>
            )
          })}
        </div>
      </div>
      <div className="space-y-4">
        <Typography.H3>Yearly Subscriptions</Typography.H3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {yearlyProducts.map((p) => {
            return (
              <div key={p.price.gateway_price_id} className="border rounded-lg p-6 shadow-sm">
                <T.H3 className="mb-2">{p.product.name}</T.H3>
                <T.P className="text-gray-600 mb-4">{p.product.description}</T.P>
                <T.H4 className="mb-2">
                  {formatGatewayPrice(p.price)}
                </T.H4>
                <ul className="list-disc list-inside mb-4"> </ul>
                <SubscriptionSelect priceId={p.price.gateway_price_id} workspaceId={workspace.id} />
              </div>
            )
          })}
        </div>
      </div>
    </div>
  );
}

async function OneTimeProducts({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  const stripePaymentGateway = new StripePaymentGateway();

  const productWithPriceListGroup = await stripePaymentGateway.anonScope.listAllOneTimeProducts();
  return (
    <div className="space-y-12">
      <div className="space-y-4">
        <Typography.H3>One-Time Products</Typography.H3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {productWithPriceListGroup.map((p) => {
            return (
              <div key={p.price.gateway_price_id} className="border rounded-lg p-6 shadow-sm">
                <T.H3 className="mb-2">{p.product.name}</T.H3>
                <T.P className="text-gray-600 mb-4">{p.product.description}</T.P>
                <T.H4 className="mb-2">
                  {formatGatewayPrice(p.price)}
                </T.H4>
                <ul className="list-disc list-inside mb-4"> </ul>
                <SubscriptionSelect isOneTimePurchase priceId={p.price.gateway_price_id} workspaceId={workspace.id} />
              </div>
            )
          })}
        </div>
      </div>
    </div>
  );
}

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function formatCurrency(amount: number, currency: string): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2,
  }).format(amount / 100); // Assuming the amount is in cents
}

function getStatusVariant(status: string): "default" | "secondary" | "destructive" | "outline" {
  switch (status.toLowerCase()) {
    case 'paid':
      return 'default';
    case 'open':
      return 'secondary';
    case 'void':
    case 'uncollectible':
      return 'destructive';
    default:
      return 'outline';
  }
}

function InvoicesTable({ invoices }: { invoices: InvoiceData[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Invoice ID</TableHead>
          <TableHead>Date</TableHead>
          <TableHead>Amount</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Product</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {invoices.map((invoice) => (
          <TableRow key={invoice.gateway_invoice_id}>
            <TableCell className="font-medium">{invoice.gateway_invoice_id}</TableCell>
            <TableCell>{invoice.paid_date ? formatDate(invoice.paid_date) : invoice.due_date ? formatDate(invoice.due_date) : 'N/A'}</TableCell>
            <TableCell>{formatCurrency(invoice.amount, invoice.currency)}</TableCell>
            <TableCell>
              <Badge variant={getStatusVariant(invoice.status)}>{invoice.status}</Badge>
            </TableCell>
            <TableCell>{invoice.billing_products?.name || 'N/A'}</TableCell>
            <TableCell>
              {invoice.hosted_invoice_url && (
                <Button variant="outline" size="sm" asChild>
                  <a href={invoice.hosted_invoice_url} target="_blank" rel="noopener noreferrer">
                    View Invoice
                  </a>
                </Button>
              )}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

async function Invoices({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  const stripePaymentGateway = new StripePaymentGateway();
  const invoices = await stripePaymentGateway.userScope.getWorkspaceDatabaseInvoices(workspace.id);

  return (
    <div className="space-y-6">
      <Typography.H3>Invoices</Typography.H3>
      <InvoicesTable invoices={invoices.data} />
    </div>
  );
}

function OneTimePurchasesTable({ purchases }: { purchases: OneTimePaymentData[] }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Purchase ID</TableHead>
          <TableHead>Date</TableHead>
          <TableHead>Amount</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Product</TableHead>
          <TableHead>Invoice</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {purchases.map((purchase) => (
          <TableRow key={purchase.gateway_charge_id}>
            <TableCell className="font-medium">{purchase.gateway_charge_id}</TableCell>
            <TableCell>{formatDate(purchase.charge_date)}</TableCell>
            <TableCell>{formatCurrency(purchase.amount, purchase.currency)}</TableCell>
            <TableCell>
              <Badge variant={getStatusVariant(purchase.status)}>{purchase.status}</Badge>
            </TableCell>
            <TableCell>{purchase.billing_products?.name || 'N/A'}</TableCell>
            <TableCell>
              {purchase.billing_invoices?.hosted_invoice_url && (
                <Button variant="outline" size="sm" asChild>
                  <a href={purchase.billing_invoices.hosted_invoice_url} target="_blank" rel="noopener noreferrer">
                    View Invoice
                  </a>
                </Button>
              )}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

async function OneTimePurchases({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  const stripePaymentGateway = new StripePaymentGateway();
  const purchases = await stripePaymentGateway.userScope.getWorkspaceDatabaseOneTimePurchases(workspace.id);

  return (
    <div className="space-y-6">
      <Typography.H3>One-Time Purchases</Typography.H3>
      <OneTimePurchasesTable purchases={purchases} />
    </div>
  );
}

export default async function WorkspaceSettingsBillingPage({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return (
    <>
      <Suspense fallback={<T.Subtle>Loading invoices...</T.Subtle>}>
        <Invoices workspace={workspace} />
      </Suspense>
      <Suspense fallback={<T.Subtle>Loading one-time purchases...</T.Subtle>}>
        <OneTimePurchases workspace={workspace} />
      </Suspense>
      <Suspense fallback={<T.Subtle>Loading subscription details...</T.Subtle>}>
        <Subscription workspace={workspace} />
      </Suspense>
      <Suspense fallback={<T.Subtle>Loading subscription products...</T.Subtle>}>
        <SubscriptionProducts workspace={workspace} />
      </Suspense>
      <Suspense fallback={<T.Subtle>Loading one-time products...</T.Subtle>}>
        <OneTimeProducts workspace={workspace} />
      </Suspense>
    </>
  );
}
