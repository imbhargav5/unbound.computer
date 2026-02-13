import { describe, expect, test, vi } from "vitest";

const { handleGatewayWebhookMock, StripeWebhookProcessingErrorMock } = vi.hoisted(() => ({
  handleGatewayWebhookMock: vi.fn(),
  StripeWebhookProcessingErrorMock: class StripeWebhookProcessingError extends Error {
    constructor(
      message: string,
      public readonly statusCode: number,
      public readonly eventId?: string,
      public readonly eventType?: string,
      public readonly cause?: unknown
    ) {
      super(message);
      this.name = "StripeWebhookProcessingError";
    }
  },
}));

vi.mock("@/payments/stripe-payment-gateway", async () => {
  return {
    StripeWebhookProcessingError: StripeWebhookProcessingErrorMock,
    StripePaymentGateway: vi.fn().mockImplementation(() => ({
      gateway: {
        handleGatewayWebhook: handleGatewayWebhookMock,
      },
    })),
  };
});

import { POST } from "./route";

describe("Stripe webhook route", () => {
  test("returns 400 when signature header is missing", async () => {
    const response = await POST(
      new Request("https://example.com/api/stripe/webhooks", {
        method: "POST",
        body: "{}",
      }) as any
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "Invalid signature" });
  });

  test("returns 200 when webhook is processed successfully", async () => {
    handleGatewayWebhookMock.mockResolvedValueOnce(undefined);

    const response = await POST(
      new Request("https://example.com/api/stripe/webhooks", {
        method: "POST",
        headers: {
          "stripe-signature": "v1=fake",
        },
        body: JSON.stringify({ id: "evt_1" }),
      }) as any
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ received: true });
    expect(handleGatewayWebhookMock).toHaveBeenCalledTimes(1);
  });

  test("returns provider error status and message", async () => {
    handleGatewayWebhookMock.mockRejectedValueOnce(
      new StripeWebhookProcessingErrorMock(
        "Invalid Stripe webhook signature or payload",
        400
      )
    );

    const response = await POST(
      new Request("https://example.com/api/stripe/webhooks", {
        method: "POST",
        headers: {
          "stripe-signature": "v1=fake",
        },
        body: "{}",
      }) as any
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: "Invalid Stripe webhook signature or payload",
    });
  });

  test("returns 500 for unknown webhook processing errors", async () => {
    handleGatewayWebhookMock.mockRejectedValueOnce(new Error("boom"));

    const response = await POST(
      new Request("https://example.com/api/stripe/webhooks", {
        method: "POST",
        headers: {
          "stripe-signature": "v1=fake",
        },
        body: "{}",
      }) as any
    );

    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ error: "Webhook processing failed" });
  });
});
