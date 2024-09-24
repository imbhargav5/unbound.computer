"use client"

import { Typography } from '@/components/ui/Typography'
import { Badge } from '@/components/ui/badge'
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { adminSyncProductsAction, adminToggleProductVisibilityAction } from '@/data/admin/billing'
import { ProductData } from '@/payments/AbstractPaymentGateway'
import { DBTable } from "@/types"
import { zodResolver } from '@hookform/resolvers/zod'
import { motion } from 'framer-motion'
import { Activity, ArrowUpRight, CreditCard, DollarSign, Users } from "lucide-react"
import { useAction } from 'next-safe-action/hooks'
import { useRouter } from 'next/navigation'
import { useRef } from "react"
import { Controller, useForm } from 'react-hook-form'
import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { toast } from 'sonner'
import { z } from 'zod'

// Mock data for charts
const revenueData = [
  { name: 'Jan', value: 4000 },
  { name: 'Feb', value: 3000 },
  { name: 'Mar', value: 5000 },
  { name: 'Apr', value: 4500 },
  { name: 'May', value: 6000 },
  { name: 'Jun', value: 5500 },
]

const customerData = [
  { name: 'Jan', value: 100 },
  { name: 'Feb', value: 120 },
  { name: 'Mar', value: 150 },
  { name: 'Apr', value: 180 },
  { name: 'May', value: 220 },
  { name: 'Jun', value: 250 },
]





interface ProductCardProps {
  product: DBTable<'billing_products'>;
}

const visibilityToggleFormSchema = z.object({
  is_visible_in_ui: z.boolean(),
});

type VisibilityToggleFormType = z.infer<typeof visibilityToggleFormSchema>;

const ProductCard: React.FC<ProductCardProps> = ({ product }) => {
  const { control } = useForm<VisibilityToggleFormType>({
    resolver: zodResolver(visibilityToggleFormSchema),
    defaultValues: {
      is_visible_in_ui: product.is_visible_in_ui,
    },
  });

  const { execute: toggleVisibility } = useAction(adminToggleProductVisibilityAction, {
    onSuccess: () => {
      toast.success("Product visibility updated successfully");
    },
    onError: ({ error }) => {
      toast.error(error.serverError || "Failed to update product visibility");
    },
  });

  const handleVisibilityToggle = (checked: boolean) => {
    toggleVisibility({ product_id: product.gateway_product_id, is_visible_in_ui: checked });
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3 }}
    >
      <Card className="w-full max-w-md">
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-2xl font-bold">{product.name}</CardTitle>
          <Badge variant={product.active ? "default" : "secondary"}>
            {product.active ? "Active" : "Inactive"}
          </Badge>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div>
              <p className="text-sm text-muted-foreground">{product.description || "No description"}</p>
            </div>
            <div className="flex justify-between items-center">
              <Label htmlFor="visible" className="text-sm font-medium">
                Show in pricing page
              </Label>
              <Controller
                name="is_visible_in_ui"
                control={control}
                render={({ field }) => (
                  <Switch
                    id="visible"
                    checked={field.value}
                    onCheckedChange={(checked) => {
                      field.onChange(checked);
                      handleVisibilityToggle(checked);
                    }}
                  />
                )}
              />
            </div>
            <div className="pt-2">
              <p className="text-xs text-muted-foreground">Gateway: {product.gateway_name}</p>
              <p className="text-xs text-muted-foreground">Product ID: {product.gateway_product_id}</p>

            </div>
          </div>
        </CardContent>
      </Card>
    </motion.div>
  );
};

export const StripeProductManager: React.FC<{ products: DBTable<'billing_products'>[] }> = ({ products }) => {

  return (
    <div className="space-y-8">
      <Typography.H4>Stripe Product Manager</Typography.H4>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {products.map((product) => (
          <ProductCard
            key={product.gateway_product_id}
            product={product}
          />
        ))}
      </div>
    </div>
  );
};


export function StripePaymentGatewayAdminPanel({
  products
}: {
  products: ProductData[]
}) {
  const toastRef = useRef<string | number | undefined>(undefined);
  const router = useRouter();
  const { execute: syncProducts, status: syncProductsStatus } = useAction(adminSyncProductsAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Syncing Stripe products...")
    },
    onSuccess: () => {
      toast.success("Stripe products synced successfully", {
        id: toastRef.current,
      })
      toastRef.current = undefined;
    },
    onError: ({ error }) => {
      toast.error(error.serverError || "Failed to sync Stripe products", {
        id: toastRef.current,
      })
      toastRef.current = undefined;
    },
  })

  const handleSyncProducts = () => {
    syncProducts({})
  }

  return (
    <div className="container mx-auto p-6">
      <Typography.H2>Admin Panel</Typography.H2>
      <StripeProductManager products={products} />
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4 mb-6">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Revenue</CardTitle>
            <DollarSign className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">$45,231.89</div>
            <p className="text-xs text-muted-foreground">+20.1% from last month</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Subscriptions</CardTitle>
            <Users className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">+2350</div>
            <p className="text-xs text-muted-foreground">+180.1% from last month</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Sales</CardTitle>
            <CreditCard className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">+12,234</div>
            <p className="text-xs text-muted-foreground">+19% from last month</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Active Now</CardTitle>
            <Activity className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">+573</div>
            <p className="text-xs text-muted-foreground">+201 since last hour</p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3 mb-6">
        <Card className="col-span-2">
          <CardHeader>
            <CardTitle>Stripe Integration</CardTitle>
            <CardDescription>Sync your Stripe data</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Button onClick={handleSyncProducts} disabled={syncProductsStatus === 'executing'}>
              {syncProductsStatus === 'executing' ? "Syncing..." : "Sync Stripe Products"}
            </Button>
            {/* <Button onClick={handleSyncCustomers} disabled={syncCustomersStatus === 'executing'}>
              {syncCustomersStatus === 'executing' ? "Syncing..." : "Sync Stripe Customers"}
            </Button> */}
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Quick Actions</CardTitle>
            <CardDescription>Useful admin options</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Button className="w-full justify-between">
              View All Customers <ArrowUpRight className="h-4 w-4" />
            </Button>
            <Button className="w-full justify-between">
              Manage Subscriptions <ArrowUpRight className="h-4 w-4" />
            </Button>
            <Button className="w-full justify-between">
              Generate Reports <ArrowUpRight className="h-4 w-4" />
            </Button>
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="revenue" className="space-y-4">
        <TabsList>
          <TabsTrigger value="revenue">Revenue</TabsTrigger>
          <TabsTrigger value="customers">Customers</TabsTrigger>
        </TabsList>
        <TabsContent value="revenue" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Revenue Overview</CardTitle>
              <CardDescription>Monthly revenue for the past 6 months</CardDescription>
            </CardHeader>
            <CardContent className="h-[300px]">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={revenueData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" />
                  <YAxis />
                  <Tooltip />
                  <Line type="monotone" dataKey="value" stroke="#8884d8" />
                </LineChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </TabsContent>
        <TabsContent value="customers" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Customer Growth</CardTitle>
              <CardDescription>Monthly customer acquisition for the past 6 months</CardDescription>
            </CardHeader>
            <CardContent className="h-[300px]">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={customerData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" />
                  <YAxis />
                  <Tooltip />
                  <Line type="monotone" dataKey="value" stroke="#82ca9d" />
                </LineChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
