import { type NextRequest, NextResponse } from "next/server";
import { reconcileBillingUsageCounters } from "@/lib/workers/reconcile-billing-usage";

function emitReconcileMetrics(metrics: {
  drift_count: number;
  dedupe_count: number;
  reconcile_failures: number;
  over_quota_transitions: number;
}) {
  console.info("[Billing Usage Reconcile Cron] metrics", metrics);
}

function validateCronAuthorization(request: NextRequest): {
  ok: boolean;
  response?: NextResponse;
} {
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret) {
    console.error("[Billing Usage Reconcile Cron] Missing CRON_SECRET");
    return {
      ok: false,
      response: NextResponse.json(
        { error: "Configuration error" },
        { status: 500 }
      ),
    };
  }

  const authHeader = request.headers.get("authorization");
  const expectedAuth = `Bearer ${cronSecret}`;
  if (authHeader !== expectedAuth) {
    return {
      ok: false,
      response: NextResponse.json({ error: "Unauthorized" }, { status: 401 }),
    };
  }

  return { ok: true };
}

async function handleReconcileRequest(request: NextRequest) {
  const auth = validateCronAuthorization(request);
  if (!auth.ok) {
    return auth.response;
  }

  try {
    const result = await reconcileBillingUsageCounters();
    emitReconcileMetrics({
      drift_count: result.driftCount,
      dedupe_count: result.dedupeCount,
      reconcile_failures: 0,
      over_quota_transitions: result.overQuotaTransitions,
    });

    return NextResponse.json({
      success: true,
      timestamp: new Date().toISOString(),
      ...result,
    });
  } catch (error) {
    emitReconcileMetrics({
      drift_count: 0,
      dedupe_count: 0,
      reconcile_failures: 1,
      over_quota_transitions: 0,
    });

    console.error(
      "[Billing Usage Reconcile Cron] Reconciliation failed",
      error
    );
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}

export async function GET(request: NextRequest) {
  return handleReconcileRequest(request);
}

export async function POST(request: NextRequest) {
  return handleReconcileRequest(request);
}
