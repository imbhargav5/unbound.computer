import { SubscriptionSelect } from "@/components/SubscriptionSelect";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { T, Typography } from "@/components/ui/Typography";
import { InvoiceData, OneTimePaymentData } from '@/payments/AbstractPaymentGateway';
import { StripePaymentGateway } from "@/payments/StripePaymentGateway";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { WorkspaceWithMembershipType } from "@/types";
import { formatGatewayPrice } from "@/utils/formatGatewayPrice";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import { Suspense } from 'react';

const formatDate = (dateString: string): string => {
  const date = new Date(dateString);
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
};

const formatCurrency = (amount: number, currency: string): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2,
  }).format(amount / 100);
};

const getStatusVariant = (status: string): "default" | "secondary" | "destructive" | "outline" => {
  switch (status.toLowerCase()) {
    case 'paid': return 'default';
    case 'open': return 'secondary';
    case 'void':
    case 'uncollectible': return 'destructive';
    default: return 'outline';
  }
};

const InvoicesTable = ({ invoices }: { invoices: InvoiceData[] }) => (
  <Table>
    <TableHeader>
      <TableRow>
        <TableHead>#</TableHead>
        <TableHead>Product</TableHead>
        <TableHead>Date</TableHead>
        <TableHead>Amount</TableHead>
        <TableHead>Status</TableHead>
        <TableHead>Actions</TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      {invoices.map((invoice, index) => (
        <TableRow key={invoice.gateway_invoice_id}>
          <TableCell className="font-medium">{index + 1}</TableCell>
          <TableCell>{invoice.billing_products?.name || 'N/A'}</TableCell>
          <TableCell>{invoice.paid_date ? formatDate(invoice.paid_date) : invoice.due_date ? formatDate(invoice.due_date) : 'N/A'}</TableCell>
          <TableCell>{formatCurrency(invoice.amount, invoice.currency)}</TableCell>
          <TableCell>
            <Badge variant={getStatusVariant(invoice.status)}>{invoice.status}</Badge>
          </TableCell>
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

const OneTimePurchasesTable = ({ purchases }: { purchases: OneTimePaymentData[] }) => (
  <Table>
    <TableHeader>
      <TableRow>
        <TableHead>#</TableHead>
        <TableHead>Product</TableHead>
        <TableHead>Date</TableHead>
        <TableHead>Amount</TableHead>
        <TableHead>Status</TableHead>
        <TableHead>Invoice</TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      {purchases.map((purchase, index) => (
        <TableRow key={purchase.gateway_charge_id}>
          <TableCell className="font-medium">{index + 1}</TableCell>
          <TableCell>{purchase.billing_products?.name || 'N/A'}</TableCell>
          <TableCell>{formatDate(purchase.charge_date)}</TableCell>
          <TableCell>{formatCurrency(purchase.amount, purchase.currency)}</TableCell>
          <TableCell>
            <Badge variant={getStatusVariant(purchase.status)}>{purchase.status}</Badge>
          </TableCell>
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

const Subscription = async ({ workspace }: { workspace: WorkspaceWithMembershipType }) => {
  const stripePaymentGateway = new StripePaymentGateway();
  try {
    const subscription = await stripePaymentGateway.userScope.getWorkspaceDatabaseSubscriptions(workspace.id);
    console.log('subscription', subscription);
    return null;
  } catch (error) {
    console.log('no subscription');
    console.error(error);
    return null;
  }
};

const SubscriptionProducts = async ({ workspace }: { workspace: WorkspaceWithMembershipType }) => {
  const stripePaymentGateway = new StripePaymentGateway();
  const productWithPriceListGroup = await stripePaymentGateway.anonScope.listAllSubscriptionProducts();
  const monthlyProducts = productWithPriceListGroup['month'] ?? [];
  const yearlyProducts = productWithPriceListGroup['year'] ?? [];

  return (
    <Tabs defaultValue="monthly">
      <TabsList>
        <TabsTrigger value="monthly">Monthly Billing</TabsTrigger>
        <TabsTrigger value="yearly">Annual Billing</TabsTrigger>
      </TabsList>
      <TabsContent value="monthly">
        <div className="space-y-8">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {monthlyProducts.map((p) => (
              <Card key={p.price.gateway_price_id}>
                <CardHeader>
                  <CardTitle>{p.product.name}</CardTitle>
                </CardHeader>
                <CardContent>
                  <T.P className="text-gray-600 mb-4">{p.product.description}</T.P>
                  <T.H4 className="mb-2">{formatGatewayPrice(p.price)}</T.H4>
                  <ul className="list-disc list-inside mb-4">Features</ul>
                  <SubscriptionSelect priceId={p.price.gateway_price_id} workspaceId={workspace.id} />
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </TabsContent>
      <TabsContent value="yearly">
        <div className="space-y-8">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {yearlyProducts.map((p) => (
              <Card key={p.price.gateway_price_id}>
                <CardHeader>
                  <CardTitle>{p.product.name}</CardTitle>
                </CardHeader>
                <CardContent>
                  <T.P className="text-gray-600 mb-4">{p.product.description}</T.P>
                  <T.H4 className="mb-2">{formatGatewayPrice(p.price)}</T.H4>
                  <ul className="list-disc list-inside mb-4">Features</ul>
                  <SubscriptionSelect priceId={p.price.gateway_price_id} workspaceId={workspace.id} />
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </TabsContent>
    </Tabs>
  );
};

const OneTimeProducts = async ({ workspace }: { workspace: WorkspaceWithMembershipType }) => {
  const stripePaymentGateway = new StripePaymentGateway();
  const productWithPriceListGroup = await stripePaymentGateway.anonScope.listAllOneTimeProducts();

  return (
    <div className="space-y-4">
      <Typography.H2>One-Time Purchases</Typography.H2>
      {productWithPriceListGroup.map((p) => (
        <Card key={p.price.gateway_price_id}>
          <CardHeader>
            <CardTitle>{p.product.name}</CardTitle>
          </CardHeader>
          <CardContent>
            <T.P className="text-gray-600 mb-4">{p.product.description}</T.P>
            <T.H4 className="mb-2">{formatGatewayPrice(p.price)}</T.H4>
            <ul className="list-disc list-inside mb-4"> </ul>
            <SubscriptionSelect isOneTimePurchase priceId={p.price.gateway_price_id} workspaceId={workspace.id} />
          </CardContent>
        </Card>
      ))}
    </div>
  )
};

const Invoices = async ({ workspace }: { workspace: WorkspaceWithMembershipType }) => {
  const stripePaymentGateway = new StripePaymentGateway();
  const invoices = await stripePaymentGateway.userScope.getWorkspaceDatabaseInvoices(workspace.id);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Invoices</CardTitle>
      </CardHeader>
      <CardContent>
        <InvoicesTable invoices={invoices.data} />
      </CardContent>
    </Card>
  );
};

const OneTimePurchases = async ({ workspace }: { workspace: WorkspaceWithMembershipType }) => {
  const stripePaymentGateway = new StripePaymentGateway();
  const purchases = await stripePaymentGateway.userScope.getWorkspaceDatabaseOneTimePurchases(workspace.id);

  return (
    <Card>
      <CardHeader>
        <CardTitle>One-Time Purchases</CardTitle>
      </CardHeader>
      <CardContent>
        <OneTimePurchasesTable purchases={purchases} />
      </CardContent>
    </Card>
  );
};

export default async function WorkspaceSettingsBillingPage({ params }: { params: unknown }) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

  return (
    <div className="space-y-8 max-w-4xl pt-6">
      <Typography.H1>Billing</Typography.H1>
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
        <Typography.H2>Plans</Typography.H2>
        <SubscriptionProducts workspace={workspace} />
      </Suspense>
      <Suspense fallback={<T.Subtle>Loading one-time products...</T.Subtle>}>
        <OneTimeProducts workspace={workspace} />
      </Suspense>
    </div>
  );
};

