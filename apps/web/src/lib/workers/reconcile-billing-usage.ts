import type { Database } from "database/types";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";

const STRIPE_GATEWAY_NAME = "stripe";
const REMOTE_COMMANDS_USAGE_TYPE = "remote_commands";

const FREE_PLAN_COMMAND_LIMIT = 50;
const PAID_PLAN_COMMAND_LIMIT = 10_000;
const UPSERT_BATCH_SIZE = 500;

type CounterIdentity = Pick<
  Database["public"]["Tables"]["billing_usage_counters"]["Row"],
  | "gateway_name"
  | "gateway_customer_id"
  | "usage_type"
  | "period_start"
  | "period_end"
>;

type UsageEventRow = Pick<
  Database["public"]["Tables"]["billing_usage_events"]["Row"],
  | "gateway_name"
  | "gateway_customer_id"
  | "usage_type"
  | "request_id"
  | "quantity"
  | "period_start"
  | "period_end"
>;

type UsageCounterRow = Pick<
  Database["public"]["Tables"]["billing_usage_counters"]["Row"],
  | "gateway_name"
  | "gateway_customer_id"
  | "usage_type"
  | "period_start"
  | "period_end"
  | "usage_count"
>;

type SubscriptionRow = Pick<
  Database["public"]["Tables"]["billing_subscriptions"]["Row"],
  | "gateway_customer_id"
  | "status"
  | "current_period_start"
  | "current_period_end"
>;

export type UsageCounterUpsertRow = Pick<
  Database["public"]["Tables"]["billing_usage_counters"]["Insert"],
  | "gateway_name"
  | "gateway_customer_id"
  | "usage_type"
  | "period_start"
  | "period_end"
> & {
  usage_count: number;
};

export type BillingUsageReconciliationResult = {
  gatewayName: string;
  usageType: string;
  eventsScanned: number;
  countersScanned: number;
  rowsRepaired: number;
  driftCount: number;
  dedupeCount: number;
  overQuotaTransitions: number;
  durationMs: number;
};

function parseTimestamp(value: string): number | null {
  const timestamp = Date.parse(value);
  if (Number.isNaN(timestamp)) {
    return null;
  }
  return timestamp;
}

function parseCounterKey(key: string): CounterIdentity {
  const parts = JSON.parse(key) as [string, string, string, string, string];
  return {
    gateway_name: parts[0],
    gateway_customer_id: parts[1],
    usage_type: parts[2],
    period_start: parts[3],
    period_end: parts[4],
  };
}

export function getCounterKey(identity: CounterIdentity): string {
  return JSON.stringify([
    identity.gateway_name,
    identity.gateway_customer_id,
    identity.usage_type,
    identity.period_start,
    identity.period_end,
  ]);
}

export function rollupUsageEvents(events: UsageEventRow[]): {
  usageTotalsByKey: Map<string, number>;
  dedupeCount: number;
} {
  const usageTotalsByKey = new Map<string, number>();
  const seenRequestIds = new Set<string>();
  let dedupeCount = 0;

  for (const event of events) {
    const requestKey = `${event.gateway_name}:${event.request_id}`;
    if (seenRequestIds.has(requestKey)) {
      dedupeCount += 1;
      continue;
    }
    seenRequestIds.add(requestKey);

    const key = getCounterKey(event);
    const previous = usageTotalsByKey.get(key) ?? 0;
    usageTotalsByKey.set(key, previous + Number(event.quantity ?? 0));
  }

  return {
    usageTotalsByKey,
    dedupeCount,
  };
}

export function buildCounterRepairPlan({
  usageTotalsByKey,
  counters,
}: {
  usageTotalsByKey: Map<string, number>;
  counters: UsageCounterRow[];
}): {
  rowsToUpsert: UsageCounterUpsertRow[];
  driftCount: number;
  existingUsageByKey: Map<string, number>;
} {
  const rowsToUpsert: UsageCounterUpsertRow[] = [];
  const existingUsageByKey = new Map<string, number>();
  let driftCount = 0;

  for (const counter of counters) {
    existingUsageByKey.set(
      getCounterKey(counter),
      Number(counter.usage_count ?? 0)
    );
  }

  for (const [key, expectedUsage] of usageTotalsByKey.entries()) {
    const existingUsage = existingUsageByKey.get(key);
    if (existingUsage === undefined || existingUsage !== expectedUsage) {
      driftCount += 1;
      rowsToUpsert.push({
        ...parseCounterKey(key),
        usage_count: expectedUsage,
      });
    }
  }

  for (const [key, existingUsage] of existingUsageByKey.entries()) {
    if (!usageTotalsByKey.has(key) && existingUsage !== 0) {
      driftCount += 1;
      rowsToUpsert.push({
        ...parseCounterKey(key),
        usage_count: 0,
      });
    }
  }

  return {
    rowsToUpsert,
    driftCount,
    existingUsageByKey,
  };
}

function hasPaidSubscriptionForPeriod({
  identity,
  subscriptions,
}: {
  identity: CounterIdentity;
  subscriptions: SubscriptionRow[];
}): boolean {
  const counterPeriodStart = parseTimestamp(identity.period_start);
  const counterPeriodEnd = parseTimestamp(identity.period_end);

  if (counterPeriodStart === null || counterPeriodEnd === null) {
    return false;
  }

  return subscriptions.some((subscription) => {
    if (subscription.gateway_customer_id !== identity.gateway_customer_id) {
      return false;
    }

    if (!["active", "trialing"].includes(subscription.status)) {
      return false;
    }

    const subscriptionStart = parseTimestamp(subscription.current_period_start);
    const subscriptionEnd = parseTimestamp(subscription.current_period_end);
    if (subscriptionStart === null || subscriptionEnd === null) {
      return false;
    }

    return (
      subscriptionStart <= counterPeriodStart &&
      subscriptionEnd >= counterPeriodEnd
    );
  });
}

export function buildCommandLimitsByKey({
  keys,
  subscriptions,
}: {
  keys: string[];
  subscriptions: SubscriptionRow[];
}): Map<string, number> {
  const limitsByKey = new Map<string, number>();

  for (const key of keys) {
    const identity = parseCounterKey(key);
    if (identity.usage_type !== REMOTE_COMMANDS_USAGE_TYPE) {
      limitsByKey.set(key, Number.MAX_SAFE_INTEGER);
      continue;
    }

    limitsByKey.set(
      key,
      hasPaidSubscriptionForPeriod({
        identity,
        subscriptions,
      })
        ? PAID_PLAN_COMMAND_LIMIT
        : FREE_PLAN_COMMAND_LIMIT
    );
  }

  return limitsByKey;
}

export function computeOverQuotaTransitions({
  rowsToUpsert,
  existingUsageByKey,
  commandLimitsByKey,
}: {
  rowsToUpsert: UsageCounterUpsertRow[];
  existingUsageByKey: Map<string, number>;
  commandLimitsByKey: Map<string, number>;
}): number {
  let transitions = 0;

  for (const row of rowsToUpsert) {
    if (row.usage_type !== REMOTE_COMMANDS_USAGE_TYPE) {
      continue;
    }

    const key = getCounterKey(row);
    const oldUsage = existingUsageByKey.get(key) ?? 0;
    const newUsage = row.usage_count;
    const limit = commandLimitsByKey.get(key) ?? FREE_PLAN_COMMAND_LIMIT;

    if (oldUsage < limit && newUsage >= limit) {
      transitions += 1;
    }
  }

  return transitions;
}

export async function reconcileBillingUsageCounters(): Promise<BillingUsageReconciliationResult> {
  const startedAt = Date.now();
  const [eventsResult, countersResult, subscriptionsResult] = await Promise.all(
    [
      supabaseAdminClient
        .from("billing_usage_events")
        .select(
          "gateway_name,gateway_customer_id,usage_type,request_id,quantity,period_start,period_end"
        )
        .eq("gateway_name", STRIPE_GATEWAY_NAME)
        .eq("usage_type", REMOTE_COMMANDS_USAGE_TYPE),
      supabaseAdminClient
        .from("billing_usage_counters")
        .select(
          "gateway_name,gateway_customer_id,usage_type,period_start,period_end,usage_count"
        )
        .eq("gateway_name", STRIPE_GATEWAY_NAME)
        .eq("usage_type", REMOTE_COMMANDS_USAGE_TYPE),
      supabaseAdminClient
        .from("billing_subscriptions")
        .select(
          "gateway_customer_id,status,current_period_start,current_period_end"
        )
        .eq("gateway_name", STRIPE_GATEWAY_NAME)
        .in("status", ["active", "trialing"]),
    ]
  );

  if (eventsResult.error) {
    throw eventsResult.error;
  }
  if (countersResult.error) {
    throw countersResult.error;
  }
  if (subscriptionsResult.error) {
    throw subscriptionsResult.error;
  }

  const events: UsageEventRow[] = eventsResult.data ?? [];
  const counters: UsageCounterRow[] = countersResult.data ?? [];
  const subscriptions: SubscriptionRow[] = subscriptionsResult.data ?? [];

  const { usageTotalsByKey, dedupeCount } = rollupUsageEvents(events);
  const { rowsToUpsert, driftCount, existingUsageByKey } =
    buildCounterRepairPlan({
      usageTotalsByKey,
      counters,
    });

  const counterKeys = rowsToUpsert.map((row) => getCounterKey(row));
  const commandLimitsByKey = buildCommandLimitsByKey({
    keys: counterKeys,
    subscriptions,
  });

  const overQuotaTransitions = computeOverQuotaTransitions({
    rowsToUpsert,
    existingUsageByKey,
    commandLimitsByKey,
  });

  if (rowsToUpsert.length > 0) {
    const nowIso = new Date().toISOString();
    for (
      let index = 0;
      index < rowsToUpsert.length;
      index += UPSERT_BATCH_SIZE
    ) {
      const batch = rowsToUpsert.slice(index, index + UPSERT_BATCH_SIZE);
      const { error } = await supabaseAdminClient
        .from("billing_usage_counters")
        .upsert(
          batch.map((row) => ({
            ...row,
            updated_at: nowIso,
          })),
          {
            onConflict:
              "gateway_name,gateway_customer_id,usage_type,period_start,period_end",
          }
        );

      if (error) {
        throw error;
      }
    }
  }

  return {
    gatewayName: STRIPE_GATEWAY_NAME,
    usageType: REMOTE_COMMANDS_USAGE_TYPE,
    eventsScanned: events.length,
    countersScanned: counters.length,
    rowsRepaired: rowsToUpsert.length,
    driftCount,
    dedupeCount,
    overQuotaTransitions,
    durationMs: Date.now() - startedAt,
  };
}
