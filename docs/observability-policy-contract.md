# Observability Policy Contract

## Purpose

This document defines the required observability policy for Unbound runtimes:

- `daemon` (Rust)
- `ios` (Swift)
- `macos` (Swift)
- `sidecar` (Falco, Nagato, daemon-ably via daemon ingestion)

It is the source of truth for:

- payload safety rules
- shared log field contract
- environment behavior
- acceptance queries and release validation checks

## Vendor Destinations

- PostHog is the primary structured log sink (`app_log` event).
- Sentry is the primary error and exception sink.
- Local debug logging remains enabled in each runtime (JSONL/OSLog/console).

## Environment Modes

Two policy modes are required in all runtimes:

1. `dev_verbose`
2. `prod_metadata_only`

### `dev_verbose`

- Full payload logging is allowed for development diagnostics.
- Known secrets must still be redacted.
- Message and structured fields are allowed for remote sinks.

### `prod_metadata_only`

- Raw payload bodies and message text are not sent to remote sinks.
- Only approved metadata fields are exported.
- A deterministic `message_hash` must be included for grouping.

## Shared Field Contract

All runtimes must emit this canonical envelope to PostHog (`app_log`):

```json
{
  "event": "app_log",
  "properties": {
    "timestamp": "2026-02-13T08:00:00.000Z",
    "runtime": "daemon",
    "service": "daemon",
    "component": "auth",
    "level": "ERROR",
    "event_code": "daemon.auth.token_refresh_failed",
    "request_id": "req_123",
    "session_id": "b1d91b4e-8e15-41e3-b16a-0fca1fa5845f",
    "device_id_hash": "sha256:...",
    "user_id_hash": "sha256:...",
    "trace_id": "7f4f1ac29f0c2b2c",
    "span_id": "f3b5b06fa8b9c921",
    "app_version": "0.1.0",
    "build_version": "20260213.1",
    "os_version": "macOS 15.0",
    "message_hash": "sha256:..."
  }
}
```

Required fields:

- `timestamp`
- `runtime`
- `service`
- `component`
- `level`
- `event_code`
- `message_hash`

Recommended when available:

- `request_id`
- `session_id`
- `device_id_hash`
- `user_id_hash`
- `trace_id`
- `span_id`
- `app_version`
- `build_version`
- `os_version`

## Correlation Canonicalization and Fallback

Runtimes must canonicalize correlation keys to snake_case before remote export:

- `request_id`
- `session_id`
- `device_id_hash`
- `user_id_hash`
- `trace_id`
- `span_id`

Alias handling (runtime-local, duplicated logic is acceptable):

- `request_id`: accept `request_id`, `requestId`, `request-id`.
- `session_id`: accept `session_id`, `sessionId`.
- `trace_id`: accept `trace_id`, `traceId`.
- `span_id`: accept `span_id`, `spanId`.
- `device_id_hash`: accept `device_id_hash`, `deviceIdHash`; fallback to `sha256(device_id|deviceId)`.
- `user_id_hash`: accept `user_id_hash`, `userIdHash`; fallback to `sha256(user_id|userId)`.

Fallback behavior when unavailable:

- If a correlation value is missing, omit the key (do not emit placeholder values).
- `device_id_hash` and `user_id_hash` must never export raw identifiers to remote sinks.
- If provided hash fields are not prefixed with `sha256:`, runtimes should hash the value and emit `sha256:<digest>`.

## Production Allowed Fields (Remote Export)

In `prod_metadata_only`, only the following fields may be exported:

- `timestamp`
- `runtime`
- `service`
- `component`
- `level`
- `event_code`
- `request_id`
- `session_id`
- `device_id_hash`
- `user_id_hash`
- `trace_id`
- `span_id`
- `app_version`
- `build_version`
- `os_version`
- `message_hash`

Explicitly disallowed in production remote export:

- raw `message`
- raw `payload`
- raw response/request bodies
- raw token values
- raw keys/secrets

## Redaction Rules

### Key denylist (case-insensitive)

- `token`
- `access_token`
- `refresh_token`
- `authorization`
- `cookie`
- `password`
- `secret`
- `private_key`
- `session_secret`
- `apnsToken`
- `pushToken`
- `content_encrypted`
- `content_nonce`

### Value-level redaction

- JWT-like values
- Bearer token patterns
- long base64/hex blobs above threshold

### Length limits

- Any string field > 512 chars must be truncated or hash-substituted before remote export.

## Sampling Policy

Default production sampling:

- `ERROR`: 100%
- `WARN`: 100%
- `INFO`: 10%
- `DEBUG`: 0% for remote sinks (local logging still allowed)

Sampling must be runtime-local and deterministic enough for validation in tests.

## Sentry Contract

Sentry tags must include:

- `runtime`
- `service`
- `component`
- `event_code`
- `request_id` (if present)
- `session_id` (if present)
- `device_id_hash` (if present)
- `user_id_hash` (if present)
- `trace_id` (if present)
- `span_id` (if present)

Sentry payloads must follow the same redaction and production metadata rules.

## Acceptance Query Checklist

Use this checklist before closing a milestone release.

### 1) No sensitive fields in production events (PostHog SQL)

```sql
SELECT count(*) AS sensitive_rows
FROM events
WHERE event = 'app_log'
  AND properties->>'environment' = 'production'
  AND (
    properties ? 'token'
    OR properties ? 'access_token'
    OR properties ? 'refresh_token'
    OR properties ? 'authorization'
    OR properties ? 'cookie'
    OR properties ? 'password'
    OR properties ? 'secret'
    OR properties ? 'private_key'
    OR properties ? 'payload'
    OR properties ? 'response_body'
    OR properties ? 'request_body'
  );
```

Expected: `0`.

### 2) Production events contain required metadata fields

```sql
SELECT count(*) AS missing_required_fields
FROM events
WHERE event = 'app_log'
  AND properties->>'environment' = 'production'
  AND (
    properties->>'runtime' IS NULL
    OR properties->>'service' IS NULL
    OR properties->>'level' IS NULL
    OR properties->>'event_code' IS NULL
    OR properties->>'message_hash' IS NULL
  );
```

Expected: `0`.

### 3) Runtime coverage check

```sql
SELECT properties->>'runtime' AS runtime, count(*) AS c
FROM events
WHERE event = 'app_log'
  AND timestamp > now() - interval '24 hours'
GROUP BY runtime
ORDER BY c DESC;
```

Expected: rows for `daemon`, `ios`, and `macos` (and `sidecar` via daemon).

### 4) Sampling sanity check

```sql
SELECT
  properties->>'level' AS level,
  count(*) AS c
FROM events
WHERE event = 'app_log'
  AND properties->>'environment' = 'production'
  AND timestamp > now() - interval '24 hours'
GROUP BY level
ORDER BY c DESC;
```

Expected: `ERROR` and `WARN` always present when generated; `INFO` volume lower than local logs.

### 5) Sentry redaction validation

Manual checks in Sentry for last 24h:

- No raw token values in event payloads.
- No raw request/response bodies in breadcrumbs.
- Tags include `runtime`, `service`, `event_code`.

Expected: pass all checks.

## Release Gate

A release is blocked if any of the following are true:

- sensitive field query returns non-zero rows
- required field query returns non-zero rows
- runtime coverage is missing one of the required runtimes
- Sentry redaction validation fails

## Ownership

- Runtime policy implementation owners: daemon, iOS, macOS maintainers.
- Contract owner: platform/observability.
- Any contract change requires updates to this document and linked tests.
