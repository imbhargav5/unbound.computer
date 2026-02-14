// src/app/api/stripe/webhooks/route.ts

import { type NextRequest, NextResponse } from "next/server";
import {
  StripePaymentGateway,
  StripeWebhookProcessingError,
} from "@/payments/stripe-payment-gateway";

export async function POST(req: NextRequest) {
  const sig = req.headers.get("stripe-signature");

  if (typeof sig !== "string") {
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  const body = await req.text();
  const stripeGateway = new StripePaymentGateway();

  try {
    await stripeGateway.gateway.handleGatewayWebhook(Buffer.from(body), sig);
    return NextResponse.json({ received: true }, { status: 200 });
  } catch (error) {
    const normalizedError =
      error instanceof StripeWebhookProcessingError
        ? error
        : new StripeWebhookProcessingError(
            "Webhook processing failed",
            500,
            undefined,
            undefined,
            error
          );

    console.error("Error processing Stripe webhook", {
      message: normalizedError.message,
      statusCode: normalizedError.statusCode,
      eventId: normalizedError.eventId,
      eventType: normalizedError.eventType,
    });

    return NextResponse.json(
      { error: normalizedError.message },
      { status: normalizedError.statusCode }
    );
  }
}

export async function GET(req: NextRequest) {
  return NextResponse.json({ ok: true });
}
