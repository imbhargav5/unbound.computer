# Observability Dashboards, Alerts, and Big-Bang Rollout Runbook

This runbook is the implementation artifact for milestone issue `NEX-865`:

- PostHog dashboards for error rate, ingestion volume, sidecar health
- Sentry alert rules for daemon/iOS/macOS error spikes and new issues
- Big-bang rollout procedure with rollback toggles
- 24-hour post-release validation checklist

Use this together with `/docs/observability-policy-contract.md`.

## 1) Runtime Toggles and Prerequisites

### Daemon (Rust)

- `UNBOUND_OBS_MODE=prod` to enforce metadata-only export.
- `UNBOUND_POSTHOG_API_KEY` (required for PostHog export).
- `UNBOUND_POSTHOG_HOST` (optional, default `https://us.i.posthog.com`).
- `UNBOUND_SENTRY_DSN` (required for Sentry export).
- Optional sampling overrides:
  - `UNBOUND_OBS_INFO_SAMPLE_RATE`
  - `UNBOUND_OBS_DEBUG_SAMPLE_RATE`
  - `UNBOUND_OBS_WARN_SAMPLE_RATE`
  - `UNBOUND_OBS_ERROR_SAMPLE_RATE`

### iOS / macOS (Swift)

- `UNBOUND_OBS_MODE=prod` to enforce metadata-only export.
- `POSTHOG_API_KEY` and optional `POSTHOG_HOST`.
- `SENTRY_DSN`.
- Optional sampling overrides:
  - `UNBOUND_OBS_INFO_SAMPLE_RATE`
  - `UNBOUND_OBS_DEBUG_SAMPLE_RATE`

## 2) PostHog Dashboard Pack

Create a dashboard named `Unbound Observability / Big Bang`.

### Card A: Ingestion Volume by Runtime (5m)

```sql
SELECT
  toStartOfInterval(timestamp, INTERVAL 5 MINUTE) AS bucket,
  properties->>'runtime' AS runtime,
  count(*) AS events
FROM events
WHERE event = 'app_log'
  AND timestamp > now() - interval '24 hours'
GROUP BY bucket, runtime
ORDER BY bucket ASC, runtime ASC;
```

Expected:

- Active rows for `daemon`, `ios`, `macos`.
- `sidecar` appears through daemon sidecar log ingestion paths.

### Card B: Error/Warn Rate by Runtime (5m)

```sql
SELECT
  toStartOfInterval(timestamp, INTERVAL 5 MINUTE) AS bucket,
  properties->>'runtime' AS runtime,
  round(
    100.0 * count(*) FILTER (
      WHERE properties->>'level' IN ('WARN', 'ERROR', 'CRITICAL')
    ) / NULLIF(count(*), 0),
    2
  ) AS error_warn_pct,
  count(*) AS total_events
FROM events
WHERE event = 'app_log'
  AND timestamp > now() - interval '24 hours'
GROUP BY bucket, runtime
ORDER BY bucket ASC, runtime ASC;
```

### Card C: Sidecar Health by Component + Event Code

```sql
SELECT
  toStartOfInterval(timestamp, INTERVAL 5 MINUTE) AS bucket,
  properties->>'component' AS component,
  properties->>'event_code' AS event_code,
  count(*) AS events
FROM events
WHERE event = 'app_log'
  AND properties->>'runtime' = 'sidecar'
  AND timestamp > now() - interval '24 hours'
GROUP BY bucket, component, event_code
ORDER BY bucket ASC, component ASC, event_code ASC;
```

Recommended filters:

- `component IN ('sidecar.falco', 'sidecar.nagato', 'sidecar.daemon-ably', 'sidecar.supervisor')`
- `event_code IN ('daemon.sidecar.log_line', 'daemon.sidecar.stream_read_failed', 'daemon.sidecar.task_join_failed')`

### Card D: Correlation Coverage by Runtime

```sql
SELECT
  properties->>'runtime' AS runtime,
  count(*) AS total,
  count(*) FILTER (WHERE properties->>'request_id' IS NOT NULL) AS with_request_id,
  count(*) FILTER (WHERE properties->>'session_id' IS NOT NULL) AS with_session_id,
  count(*) FILTER (WHERE properties->>'trace_id' IS NOT NULL) AS with_trace_id,
  count(*) FILTER (WHERE properties->>'span_id' IS NOT NULL) AS with_span_id
FROM events
WHERE event = 'app_log'
  AND properties->>'environment' = 'production'
  AND timestamp > now() - interval '24 hours'
GROUP BY runtime
ORDER BY runtime ASC;
```

## 3) Sentry Alert Rules

Create these alert rules for environment `production`.

### Rule 1: Daemon Error Spike

- Filter: `tags.runtime:daemon`
- Trigger: event count `>= 20` in `5m`
- Levels: `error`, `fatal`
- Actions: notify on-call Slack + PagerDuty

### Rule 2: iOS Error Spike

- Filter: `tags.runtime:ios`
- Trigger: event count `>= 20` in `5m`
- Levels: `error`, `fatal`
- Actions: notify mobile Slack + on-call Slack

### Rule 3: macOS Error Spike

- Filter: `tags.runtime:macos`
- Trigger: event count `>= 20` in `5m`
- Levels: `error`, `fatal`
- Actions: notify desktop Slack + on-call Slack

### Rule 4: New Production Issue

- Trigger: new issue created in `production`
- Required tags: `runtime`, `service`, `event_code`
- Actions: notify on-call Slack (immediate)

### Rule 5: Sidecar Pipeline Failures

- Filter: `tags.runtime:sidecar` or `tags.component:sidecar.*`
- Trigger: `event_code=daemon.sidecar.stream_read_failed` count `>= 3` in `10m`
- Actions: notify daemon owners + on-call Slack

## 4) Big-Bang Rollout Procedure

### T-1 Day (Preparation)

- Confirm env/config secrets are provisioned for all runtimes.
- Validate `UNBOUND_OBS_MODE=prod` in staging.
- Validate PostHog dashboard cards return data in staging.
- Create and test Sentry alert rules with synthetic test events.

### T0 (Release Window)

1. Deploy daemon with:
   - `UNBOUND_OBS_MODE=prod`
   - PostHog + Sentry credentials
2. Release macOS build with `POSTHOG_API_KEY` and `SENTRY_DSN`.
3. Release iOS build with `POSTHOG_API_KEY` and `SENTRY_DSN`.
4. Verify first 15 minutes:
   - runtime coverage (`daemon`, `ios`, `macos`, `sidecar`)
   - no sensitive-field leakage query failures
   - error/warn rates within baseline

### T+15m and T+60m (Stabilization Checks)

- Re-run dashboard and acceptance queries.
- Confirm no runaway ingestion spikes.
- Confirm Sentry alerts are firing only on real errors.

## 5) Rollback Toggles

If remote observability causes incident risk:

1. Daemon rollback (fastest):
   - unset `UNBOUND_POSTHOG_API_KEY` and `UNBOUND_SENTRY_DSN`
   - restart daemon
2. iOS/macOS rollback:
   - remove `POSTHOG_API_KEY` and `SENTRY_DSN` from runtime config for next hotfix build
   - keep local logging active
3. Sampling-based relief (temporary):
   - lower `UNBOUND_OBS_INFO_SAMPLE_RATE` to reduce volume
   - keep warn/error unsampled

## 6) 24-Hour Post-Release Checklist

- [ ] `app_log` ingestion present for `daemon`, `ios`, `macos`, `sidecar`.
- [ ] Sensitive-field leakage query returns `0`.
- [ ] Required field query returns `0`.
- [ ] Correlation fields are present and queryable by runtime.
- [ ] No sustained error/warn spike relative to baseline.
- [ ] Sidecar failure events do not exceed threshold:
  - `daemon.sidecar.stream_read_failed < 3 per 10m`
  - `daemon.sidecar.task_join_failed = 0`
- [ ] Sentry new-issue alerts triggered and routed correctly.
- [ ] Rollback toggles tested in staging and documented in release notes.

## 7) Sign-off

Required sign-off roles:

- Daemon owner
- iOS owner
- macOS owner
- Observability owner
- On-call approver for release window
