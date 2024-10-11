"use server";

import { adminActionClient } from "@/lib/safe-action";
import { StripePaymentGateway } from "@/payments/StripePaymentGateway";
import { revalidatePath } from "next/cache";
import { z } from "zod";

// Create a schema for the sync plans action
const syncPlansSchema = z.object({});

// Create the adminSyncProductsAction
export const adminSyncProductsAction = adminActionClient
  .schema(syncPlansSchema)
  .action(async () => {
    const stripeGateway = new StripePaymentGateway();
    await stripeGateway.superAdminScope.syncProducts();
    revalidatePath("/", "layout");
  });

const visibilityToggleSchema = z.object({
  product_id: z.string(),
  is_visible_in_ui: z.boolean(),
});

export const adminToggleProductVisibilityAction = adminActionClient
  .schema(visibilityToggleSchema)
  .action(async ({ parsedInput: { product_id, is_visible_in_ui } }) => {
    const stripeGateway = new StripePaymentGateway();
    await stripeGateway.superAdminScope.toggleProductVisibility(
      product_id,
      is_visible_in_ui,
    );
    revalidatePath("/", "layout");
  });
