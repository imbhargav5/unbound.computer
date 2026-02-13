import { type NextRequest, NextResponse } from "next/server";
import {
  assertUserOwnsDevice,
  buildUsageStatusPayload,
  corsHeaders,
  ensureStripeBillingCustomer,
  getBillingWindow,
  getUsageCount,
  requireMobileUser,
  usageStatusQuerySchema,
} from "../shared";

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

export async function GET(req: NextRequest) {
  try {
    const { userId, mobileClient } = await requireMobileUser(req);

    const { searchParams } = new URL(req.url);
    const parseResult = usageStatusQuerySchema.safeParse({
      deviceId: searchParams.get("deviceId"),
    });

    if (!parseResult.success) {
      return NextResponse.json(
        { error: "Invalid request query", details: parseResult.error.issues },
        { status: 400, headers: corsHeaders }
      );
    }

    const { deviceId } = parseResult.data;
    await assertUserOwnsDevice({
      mobileClient,
      userId,
      deviceId,
    });

    const customer = await ensureStripeBillingCustomer(userId);
    const window = await getBillingWindow(customer.gateway_customer_id);
    const commandsUsed = await getUsageCount({
      gatewayCustomerId: customer.gateway_customer_id,
      usageType: "remote_commands",
      periodStart: window.periodStart,
      periodEnd: window.periodEnd,
    });

    return NextResponse.json(
      buildUsageStatusPayload({
        plan: window.plan,
        periodStart: window.periodStart,
        periodEnd: window.periodEnd,
        commandsLimit: window.commandsLimit,
        commandsUsed,
      }),
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

