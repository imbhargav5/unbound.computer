import { T } from "@/components/ui/Typography";
import { workspaceSlugParamSchema } from "@/utils/zod-schemas/params";
import { Suspense } from "react";

import { StripePaymentGateway } from "@/payments/StripePaymentGateway";
import { getCachedWorkspaceBySlug } from "@/rsc-data/user/workspaces";
import { WorkspaceWithMembershipType } from "@/types";
import type { Metadata } from "next";

async function Subscription({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  const stripePaymentGateway = new StripePaymentGateway();

  try {
    const subscription = await stripePaymentGateway.userScope.getWorkspaceDatabaseSubscriptions(workspace.id);
  } catch (error) {
    const plans = await stripePaymentGateway.anonScope.listVisiblePlans();
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {plans.map((plan) => (
          <div key={plan.gateway_plan_id} className="border rounded-lg p-6 shadow-sm">
            <T.H3 className="mb-2">{plan.name}</T.H3>
            <T.P className="text-gray-600 mb-4">{plan.description}</T.P>
            <T.H4 className="mb-2">
              {plan.billing_plan_prices[0]?.amount
                ? `$${(plan.billing_plan_prices[0].amount / 100).toFixed(2)}`
                : 'Custom pricing'}
              {plan.billing_plan_prices[0]?.recurring_interval &&
                `/${plan.billing_plan_prices[0].recurring_interval}`}
            </T.H4>
            <ul className="list-disc list-inside mb-4">
              Features
            </ul>
            <button className="w-full bg-blue-600 text-white py-2 px-4 rounded hover:bg-blue-700 transition-colors">
              Select Plan
            </button>
          </div>
        ))}
      </div>
    );
  }
}

export const metadata: Metadata = {
  title: "Billing",
  description: "You can edit your organization's billing details here.",
};

export default async function OrganizationSettingsPage({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return (
    <Suspense fallback={<T.Subtle>Loading billing details...</T.Subtle>}>
      <Subscription workspace={workspace} />
    </Suspense>
  );
}
