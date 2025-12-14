import { Suspense } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { T, Typography } from "@/components/ui/typography-ui";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { CustomerDetailsServer } from "./customer-details-server";
import { OneTimeProductsServer } from "./one-time-products-server";
import { SubscriptionProductsServer } from "./subscription-products-server";

export async function WorkspaceBilling({
  workspaceSlug,
}: {
  workspaceSlug: string;
}) {
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      <div className="mb-12 text-center">
        <Typography.H1 className="mb-2 font-bold text-4xl">
          Workspace Billing
        </Typography.H1>
        <T.P className="text-gray-600 text-xl dark:text-gray-300">
          Manage your subscriptions and payments
        </T.P>
      </div>

      <Suspense
        fallback={
          <Card>
            <CardContent>
              <T.Subtle>Loading customer details...</T.Subtle>
            </CardContent>
          </Card>
        }
      >
        <CustomerDetailsServer workspace={workspace} />
      </Suspense>

      <Suspense
        fallback={
          <Card>
            <CardContent>
              <T.Subtle>Loading subscription products...</T.Subtle>
            </CardContent>
          </Card>
        }
      >
        <SubscriptionProductsServer workspace={workspace} />
      </Suspense>

      <Suspense
        fallback={
          <Card>
            <CardContent>
              <T.Subtle>Loading one-time products...</T.Subtle>
            </CardContent>
          </Card>
        }
      >
        <OneTimeProductsServer workspace={workspace} />
      </Suspense>
    </div>
  );
}
