import type { NextRequest } from "next/server";
import { z } from "zod";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { createSupabaseMobileClient } from "@/supabase-clients/mobile/create-supabase-mobile-client";
import { StripePaymentGateway } from "@/payments/stripe-payment-gateway";

export const usageTypeSchema = z.enum(["remote_commands"]);
export type UsageType = z.infer<typeof usageTypeSchema>;

export const usageEventsRequestSchema = z.object({
  deviceId: z.string().uuid(),
  requestId: z.string().uuid(),
  usageType: usageTypeSchema.default("remote_commands"),
  quantity: z.number().int().positive().default(1),
  occurredAt: z.string().datetime().optional(),
});

export const usageStatusQuerySchema = z.object({
  deviceId: z.string().uuid(),
});

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const FREE_PLAN_COMMAND_LIMIT = 50;
const PAID_PLAN_COMMAND_LIMIT = 10_000;
const NEAR_LIMIT_THRESHOLD_RATIO = 0.1;

export type EnforcementState = "ok" | "near_limit" | "over_quota";

export type BillingWindow = {
  plan: "free" | "paid";
  periodStart: string;
  periodEnd: string;
  commandsLimit: number;
};

function startOfCurrentMonthUtc(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
}

function endOfCurrentMonthUtc(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
}

export function computeEnforcementState(
  commandsUsed: number,
  commandsLimit: number
): EnforcementState {
  if (commandsUsed >= commandsLimit) {
    return "over_quota";
  }

  if (commandsUsed >= Math.floor(commandsLimit * (1 - NEAR_LIMIT_THRESHOLD_RATIO))) {
    return "near_limit";
  }

  return "ok";
}

export function buildUsageStatusPayload({
  plan,
  periodStart,
  periodEnd,
  commandsLimit,
  commandsUsed,
}: {
  plan: BillingWindow["plan"];
  periodStart: string;
  periodEnd: string;
  commandsLimit: number;
  commandsUsed: number;
}) {
  const safeUsed = Math.max(commandsUsed, 0);
  const commandsRemaining = Math.max(commandsLimit - safeUsed, 0);

  return {
    plan,
    gateway: "stripe",
    periodStart,
    periodEnd,
    commandsLimit,
    commandsUsed: safeUsed,
    commandsRemaining,
    enforcementState: computeEnforcementState(safeUsed, commandsLimit),
    updatedAt: new Date().toISOString(),
  };
}

export async function requireMobileUser(
  req: NextRequest
): Promise<{ userId: string; mobileClient: ReturnType<typeof createSupabaseMobileClient> }> {
  const mobileClient = createSupabaseMobileClient(req);
  const {
    data: { user },
  } = await mobileClient.auth.getUser();

  if (!user) {
    throw new Error("Unauthorized");
  }

  return {
    userId: user.id,
    mobileClient,
  };
}

export async function assertUserOwnsDevice({
  mobileClient,
  userId,
  deviceId,
}: {
  mobileClient: ReturnType<typeof createSupabaseMobileClient>;
  userId: string;
  deviceId: string;
}): Promise<void> {
  const { data: device, error } = await mobileClient
    .from("devices")
    .select("id, user_id")
    .eq("id", deviceId)
    .single();

  if (error || !device) {
    throw new Error("Device not found");
  }

  if (device.user_id !== userId) {
    throw new Error("Forbidden");
  }
}

export async function ensureStripeBillingCustomer(userId: string) {
  const stripeGateway = new StripePaymentGateway();
  const existing = await stripeGateway.util.getCustomerByUserId(userId);
  if (existing) return existing;
  return stripeGateway.util.createCustomerForUser(userId);
}

export async function getBillingWindow(
  gatewayCustomerId: string
): Promise<BillingWindow> {
  const { data: subscription, error } = await supabaseAdminClient
    .from("billing_subscriptions")
    .select("status, current_period_start, current_period_end")
    .eq("gateway_name", "stripe")
    .eq("gateway_customer_id", gatewayCustomerId)
    .in("status", ["active", "trialing"])
    .order("current_period_end", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (subscription) {
    return {
      plan: "paid",
      periodStart: subscription.current_period_start,
      periodEnd: subscription.current_period_end,
      commandsLimit: PAID_PLAN_COMMAND_LIMIT,
    };
  }

  const now = new Date();
  return {
    plan: "free",
    periodStart: startOfCurrentMonthUtc(now).toISOString(),
    periodEnd: endOfCurrentMonthUtc(now).toISOString(),
    commandsLimit: FREE_PLAN_COMMAND_LIMIT,
  };
}

export async function recordBillingUsageEvent({
  gatewayCustomerId,
  usageType,
  requestId,
  periodStart,
  periodEnd,
  quantity,
  occurredAt,
}: {
  gatewayCustomerId: string;
  usageType: UsageType;
  requestId: string;
  periodStart: string;
  periodEnd: string;
  quantity: number;
  occurredAt?: string;
}): Promise<number | null> {
  const adminClient = supabaseAdminClient as any;
  const { data, error } = await adminClient.rpc("record_billing_usage_event", {
    p_gateway_name: "stripe",
    p_gateway_customer_id: gatewayCustomerId,
    p_usage_type: usageType,
    p_request_id: requestId,
    p_period_start: periodStart,
    p_period_end: periodEnd,
    p_quantity: quantity,
    p_event_timestamp: occurredAt ?? new Date().toISOString(),
    p_metadata: {},
  });

  if (error) {
    throw error;
  }

  return data?.usage_count ?? null;
}

export async function getUsageCount({
  gatewayCustomerId,
  usageType,
  periodStart,
  periodEnd,
}: {
  gatewayCustomerId: string;
  usageType: UsageType;
  periodStart: string;
  periodEnd: string;
}): Promise<number> {
  const adminClient = supabaseAdminClient as any;
  const { data, error } = await adminClient
    .from("billing_usage_counters")
    .select("usage_count")
    .eq("gateway_name", "stripe")
    .eq("gateway_customer_id", gatewayCustomerId)
    .eq("usage_type", usageType)
    .eq("period_start", periodStart)
    .eq("period_end", periodEnd)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return Number(data?.usage_count ?? 0);
}
