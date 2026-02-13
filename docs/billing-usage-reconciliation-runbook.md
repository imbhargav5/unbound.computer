# Billing Usage Reconciliation Runbook

This runbook covers operational handling for Stripe async usage metering reconciliation (`NEX-857`).

## Scope

- Endpoint: `GET/POST /api/cron/billing/reconcile-usage`
- Schedule: every 5 minutes (see `apps/web/vercel.json`)
- Auth: `Authorization: Bearer $CRON_SECRET`
- Data surfaces:
  - `billing_usage_events` (idempotent event log)
  - `billing_usage_counters` (enforcement counters)

## What reconciliation does

1. Reads Stripe `remote_commands` events and aggregates usage by:
   - `gateway_name`
   - `gateway_customer_id`
   - `usage_type`
   - `period_start`
   - `period_end`
2. Compares aggregates with persisted counters.
3. Repairs drift by upserting corrected `usage_count`.
4. Sets orphaned counters (no events backing them) to `0`.
5. Emits metrics logs:
   - `drift_count`
   - `dedupe_count`
   - `reconcile_failures`
   - `over_quota_transitions`

## Normal verification

1. Confirm recent successful cron runs in Vercel logs for `/api/cron/billing/reconcile-usage`.
2. Confirm metrics log line exists and `reconcile_failures=0`.
3. Spot-check repaired rows when `drift_count > 0`.

## Incident response

### A) `reconcile_failures > 0`

1. Check logs for the failing query/upsert error.
2. Validate environment:
   - `CRON_SECRET`
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
3. Re-run endpoint manually with cron auth after fix.

### B) Unexpected quota denials (`over_quota_transitions` spike)

1. Compare pre/post counter values for affected customer-period rows.
2. Verify event volume for same rows:
   - If events are valid, transition is expected enforcement.
   - If events are suspicious, investigate producer IDs (`request_id`, device context in metadata).
3. If needed, temporarily remediate by correcting affected counter rows and re-running reconciliation.

## Replay and backfill

If ingestion outage caused missed counters:

1. Ensure historical events exist in `billing_usage_events`.
2. Trigger reconciliation endpoint (manual authorized run) to rebuild counters.
3. Validate counters match event sums for impacted customer + period keys.

If events are missing entirely:

1. Backfill events from source audit/log system with deterministic `request_id`.
2. Trigger reconciliation endpoint again.
3. Validate repaired counters and monitor `drift_count` returning toward zero.

## Rollback / safety

If reconciliation causes operational risk:

1. Disable or remove cron entry for `/api/cron/billing/reconcile-usage`.
2. Keep usage ingestion active; this only pauses auto-healing.
3. Perform targeted manual reconciliation after root-cause fix.
