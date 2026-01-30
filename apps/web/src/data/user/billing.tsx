"use server";
import { z } from "zod";
import { authActionClient } from "@/lib/safe-action";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";

const createCheckoutSessionSchema = z.object({
  priceId: z.string(),
});

export const createUserCheckoutSession = authActionClient
  .inputSchema(createCheckoutSessionSchema)
  .action(async ({ parsedInput: { priceId }, ctx: { userId } }) => {
    const stripePaymentGateway = new StripePaymentGateway();
    return await stripePaymentGateway.userScope.createGatewayCheckoutSession({
      userId,
      priceId,
    });
  });
