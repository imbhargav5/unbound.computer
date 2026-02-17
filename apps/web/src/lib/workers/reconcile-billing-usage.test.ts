import { beforeAll, describe, expect, test } from "vitest";
import type { UsageCounterUpsertRow } from "./reconcile-billing-usage";

type WorkerModule = typeof import("./reconcile-billing-usage");
let worker: WorkerModule;

beforeAll(async () => {
  process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://example.supabase.co";
  process.env.SUPABASE_SECRET_KEY ??= "test-service-role-key";
  worker = await import("./reconcile-billing-usage");
});

function buildCounterIdentity(
  overrides?: Partial<UsageCounterUpsertRow>
): UsageCounterUpsertRow {
  return {
    gateway_name: "stripe",
    gateway_customer_id: "cus_123",
    usage_type: "remote_commands",
    period_start: "2026-02-01T00:00:00.000Z",
    period_end: "2026-03-01T00:00:00.000Z",
    usage_count: 1,
    ...overrides,
  };
}

describe("rollupUsageEvents", () => {
  test("dedupes duplicate request ids and reports dedupe_count", () => {
    const { usageTotalsByKey, dedupeCount } = worker.rollupUsageEvents([
      {
        ...buildCounterIdentity(),
        request_id: "req-1",
        quantity: 1,
      },
      {
        ...buildCounterIdentity(),
        request_id: "req-1",
        quantity: 4,
      },
      {
        ...buildCounterIdentity(),
        request_id: "req-2",
        quantity: 2,
      },
    ]);

    expect(dedupeCount).toBe(1);
    expect(usageTotalsByKey.size).toBe(1);
    expect(usageTotalsByKey.values().next().value).toBe(3);
  });
});

describe("buildCounterRepairPlan", () => {
  test("repairs mismatched counters and zeroes orphaned counters", () => {
    const primary = buildCounterIdentity({
      gateway_customer_id: "cus_primary",
      usage_count: 5,
    });
    const secondary = buildCounterIdentity({
      gateway_customer_id: "cus_secondary",
      usage_count: 2,
    });
    const orphan = buildCounterIdentity({
      gateway_customer_id: "cus_orphan",
      usage_count: 7,
    });

    const usageTotalsByKey = new Map<string, number>([
      [worker.getCounterKey(primary), 5],
      [worker.getCounterKey(secondary), 9],
    ]);

    const { rowsToUpsert, driftCount } = worker.buildCounterRepairPlan({
      usageTotalsByKey,
      counters: [
        { ...primary, usage_count: 5 },
        { ...secondary, usage_count: 2 },
        { ...orphan, usage_count: 7 },
      ],
    });

    expect(driftCount).toBe(2);
    expect(rowsToUpsert).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          gateway_customer_id: "cus_secondary",
          usage_count: 9,
        }),
        expect.objectContaining({
          gateway_customer_id: "cus_orphan",
          usage_count: 0,
        }),
      ])
    );
  });
});

describe("computeOverQuotaTransitions", () => {
  test("counts transitions where corrected usage crosses command limits", () => {
    const freePlanRow = buildCounterIdentity({
      gateway_customer_id: "cus_free",
      usage_count: 51,
    });
    const paidPlanRow = buildCounterIdentity({
      gateway_customer_id: "cus_paid",
      period_start: "2026-02-10T00:00:00.000Z",
      period_end: "2026-03-10T00:00:00.000Z",
      usage_count: 10_005,
    });

    const rowsToUpsert = [freePlanRow, paidPlanRow];
    const existingUsageByKey = new Map<string, number>([
      [worker.getCounterKey(freePlanRow), 49],
      [worker.getCounterKey(paidPlanRow), 9999],
    ]);

    const commandLimitsByKey = worker.buildCommandLimitsByKey({
      keys: rowsToUpsert.map((row) => worker.getCounterKey(row)),
      subscriptions: [
        {
          gateway_customer_id: "cus_paid",
          status: "active",
          current_period_start: "2026-02-10T00:00:00.000Z",
          current_period_end: "2026-03-10T00:00:00.000Z",
        },
      ],
    });

    const transitions = worker.computeOverQuotaTransitions({
      rowsToUpsert,
      existingUsageByKey,
      commandLimitsByKey,
    });

    expect(transitions).toBe(2);
  });
});
