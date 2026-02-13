import { beforeAll, describe, expect, test } from "vitest";

type SharedModule = typeof import("./shared");
let shared: SharedModule;

beforeAll(async () => {
  process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://example.supabase.co";
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??= "test-publishable-key";
  process.env.SUPABASE_SECRET_KEY ??= "test-service-role-key";
  shared = await import("./shared");
});

describe("billing usage schemas", () => {
  test("usage-events schema applies defaults", () => {
    const parsed = shared.usageEventsRequestSchema.parse({
      deviceId: "6f5db7f9-c6ef-4d60-88f8-39f62f272f07",
      requestId: "8d34654a-9317-4052-bfca-32f4f695f2b4",
    });

    expect(parsed.usageType).toBe("remote_commands");
    expect(parsed.quantity).toBe(1);
  });

  test("usage-status query schema validates UUID", () => {
    const valid = shared.usageStatusQuerySchema.safeParse({
      deviceId: "6f5db7f9-c6ef-4d60-88f8-39f62f272f07",
    });
    const invalid = shared.usageStatusQuerySchema.safeParse({
      deviceId: "not-a-uuid",
    });

    expect(valid.success).toBe(true);
    expect(invalid.success).toBe(false);
  });
});

describe("billing usage payload contract", () => {
  test("computes over-quota and near-limit states", () => {
    expect(shared.computeEnforcementState(100, 100)).toBe("over_quota");
    expect(shared.computeEnforcementState(91, 100)).toBe("near_limit");
    expect(shared.computeEnforcementState(10, 100)).toBe("ok");
  });

  test("builds payload with remaining quota and gateway", () => {
    const payload = shared.buildUsageStatusPayload({
      plan: "free",
      periodStart: "2026-02-01T00:00:00.000Z",
      periodEnd: "2026-03-01T00:00:00.000Z",
      commandsLimit: 50,
      commandsUsed: 12,
    });

    expect(payload.gateway).toBe("stripe");
    expect(payload.commandsRemaining).toBe(38);
    expect(payload.enforcementState).toBe("ok");
  });
});
