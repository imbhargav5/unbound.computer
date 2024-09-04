import { T } from "@/components/ui/Typography";
import {
  getLoggedInUserOrganizationRole,
  getNormalizedOrganizationSubscription,
  getOrganizationIdBySlug,
} from "@/data/user/organizations";
import { organizationSlugParamSchema } from "@/utils/zod-schemas/params";
import { Suspense } from "react";

import type { Metadata } from "next";
import { OrganizationSubscripionDetails } from "./OrganizationSubscripionDetails";

async function Subscription({ organizationId }: { organizationId: string }) {
  const normalizedSubscription =
    await getNormalizedOrganizationSubscription(organizationId);
  const organizationRole =
    await getLoggedInUserOrganizationRole(organizationId);
  return (
    <OrganizationSubscripionDetails
      organizationId={organizationId}
      organizationRole={organizationRole}
      normalizedSubscription={normalizedSubscription}
    />
  );
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
  const { organizationSlug } = organizationSlugParamSchema.parse(params);
  const organizationId = await getOrganizationIdBySlug(organizationSlug);
  return (
    <Suspense fallback={<T.Subtle>Loading billing details...</T.Subtle>}>
      <Subscription organizationId={organizationId} />
    </Suspense>
  );
}
