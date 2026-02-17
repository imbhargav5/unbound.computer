import { type NextRequest, NextResponse } from "next/server";
import {
  assertUserOwnsDevice,
  buildUsageStatusPayload,
  corsHeaders,
  ensureStripeBillingCustomer,
  getBillingWindow,
  getUsageCount,
  recordBillingUsageEvent,
  requireMobileUser,
  usageEventsRequestSchema,
} from "../shared";

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

export async function POST(req: NextRequest) {
  try {
    const { userId, mobileClient } = await requireMobileUser(req);

    const body = await req.json();
    const parseResult = usageEventsRequestSchema.safeParse(body);
    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request body", details: parseResult.error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    const { deviceId, requestId, usageType, quantity, occurredAt } =
      parseResult.data;
    await assertUserOwnsDevice({
      mobileClient,
      userId,
      deviceId,
    });

    const customer = await ensureStripeBillingCustomer(userId);
    const window = await getBillingWindow(customer.gateway_customer_id);

    const usageCountFromRecord = await recordBillingUsageEvent({
      gatewayCustomerId: customer.gateway_customer_id,
      usageType,
      requestId,
      periodStart: window.periodStart,
      periodEnd: window.periodEnd,
      quantity,
      occurredAt,
    });

    const commandsUsed =
      usageCountFromRecord ??
      (await getUsageCount({
        gatewayCustomerId: customer.gateway_customer_id,
        usageType,
        periodStart: window.periodStart,
        periodEnd: window.periodEnd,
      }));

    return NextResponse.json(
      {
        accepted: true,
        requestId,
        usageType,
        ...buildUsageStatusPayload({
          plan: window.plan,
          periodStart: window.periodStart,
          periodEnd: window.periodEnd,
          commandsLimit: window.commandsLimit,
          commandsUsed,
        }),
      },
      { headers: corsHeaders }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    if (message === "Unauthorized") {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401, headers: corsHeaders }
      );
    }

    if (message === "Device not found") {
      return NextResponse.json(
        { error: "Device not found" },
        { status: 404, headers: corsHeaders }
      );
    }

    if (message === "Forbidden") {
      return NextResponse.json(
        { error: "Forbidden" },
        { status: 403, headers: corsHeaders }
      );
    }

    return NextResponse.json(
      { error: message },
      { status: 500, headers: corsHeaders }
    );
  }
}
