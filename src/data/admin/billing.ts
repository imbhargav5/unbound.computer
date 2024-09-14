'use server';

import { adminActionClient } from '@/lib/safe-action';
import { StripePaymentGateway } from '@/payments/StripePaymentGateway';
import { revalidatePath } from 'next/cache';
import { z } from 'zod';

// Create a schema for the sync plans action
const syncPlansSchema = z.object({});

// Create the adminSyncPlansAction
export const adminSyncPlansAction = adminActionClient
  .schema(syncPlansSchema)
  .action(async () => {
    const stripeGateway = new StripePaymentGateway();
    await stripeGateway.superAdminScope.syncPlans();
    revalidatePath('/', 'layout');
  });


const visibilityToggleSchema = z.object({
  plan_id: z.string(),
  is_visible_in_ui: z.boolean(),
});

export const adminTogglePlanVisibilityAction = adminActionClient
  .schema(visibilityToggleSchema)
  .action(async ({ parsedInput: { plan_id, is_visible_in_ui } }) => {
    const stripeGateway = new StripePaymentGateway();
    await stripeGateway.superAdminScope.togglePlanVisibility(plan_id, is_visible_in_ui);
    revalidatePath('/', 'layout');
  });
