"use server";
import { z } from "zod";
import { authActionClient } from "@/lib/safe-action";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";

const createCheckoutSessionSchema = z.object({
  priceId: z.string(),
  workspaceId: z.string(),
});

export const createWorkspaceCheckoutSession = authActionClient
  .inputSchema(createCheckoutSessionSchema)
  .action(async ({ parsedInput: { priceId, workspaceId } }) => {
    const stripePaymentGateway = new StripePaymentGateway();
    return await stripePaymentGateway.userScope.createGatewayCheckoutSession({
      workspaceId,
      priceId,
    });
  });
