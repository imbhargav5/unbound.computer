"use server";

import { z } from "zod";
import { adminActionClient } from "@/lib/safe-action";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";

// Create a schema for the sync plans action
const syncPlansSchema = z.object({});

/**
 * Admin action to synchronize products with the Stripe payment gateway.
 * Utilizes the adminActionClient to define the schema and action.
 */
export const adminSyncProductsAction = adminActionClient
  .inputSchema(syncPlansSchema)
  .action(async () => {
    const stripeGateway = new StripePaymentGateway();
    // Synchronize products in the super admin scope
    await stripeGateway.superAdminScope.syncProducts();
  });

// Schema for toggling product visibility
const visibilityToggleSchema = z.object({
  product_id: z.string(),
  is_visible_in_ui: z.boolean(),
});

/**
 * Admin action to toggle the visibility of a product in the UI.
 * Uses the adminActionClient to define the schema and action.
 * @param parsedInput - Contains product_id and visibility status
 */
export const adminToggleProductVisibilityAction = adminActionClient
  .inputSchema(visibilityToggleSchema)
  .action(async ({ parsedInput: { product_id, is_visible_in_ui } }) => {
    const stripeGateway = new StripePaymentGateway();
    // Toggle the visibility of the product in the super admin scope
    await stripeGateway.superAdminScope.toggleProductVisibility(
      product_id,
      is_visible_in_ui
    );
  });
