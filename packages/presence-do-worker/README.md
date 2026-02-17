# presence-do-worker

Cloudflare Worker that fronts the presence Durable Object, validating ingress tokens for heartbeats and issuing SSE streams for mobile clients.

This worker is the HTTP entrypoint for presence updates. It routes requests to the per-user Durable Object instance and handles auth, payload validation, CORS, and stream fanout.

## Responsibilities

- **Heartbeat ingestion**: validate daemon heartbeat payloads + ingest token before writing to Durable Object storage.
- **Presence stream**: authenticate HMAC-signed tokens and stream SSE updates for all devices under a user.
- **TTL enforcement**: schedule alarms to mark stale devices offline when heartbeat TTLs expire.

## Routes

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/api/v1/daemon/presence/heartbeat` | Ingests daemon heartbeats and updates device presence records. |
| `GET` | `/api/v1/mobile/presence/stream?user_id=...` | Streams presence events as SSE for a user. |
| `OPTIONS` | `*` | CORS preflight. |

Both routes are routed to the per-user Durable Object instance using `PRESENCE_DO.idFromName(user_id)`.

## Auth + Validation

- **Heartbeat** requests require `Authorization: Bearer $PRESENCE_DO_INGEST_TOKEN`.
- **Stream** requests require `Authorization: Bearer <presence-token>` where the token is an HMAC-SHA256 signed payload.
- Tokens must include `presence:read` in `scope` and match the `user_id` query param.
- Device + user IDs must be lowercase UUIDs. Non-monotonic `seq` values are rejected with `409`.

## Event Flow

1. Daemon posts heartbeat payloads to `/api/v1/daemon/presence/heartbeat`.
2. Worker validates, persists the record, and broadcasts an SSE event.
3. Streams emit the latest known state for all devices on connect.
4. Alarms flip devices to `offline` after TTL expiry and broadcast the update.

## Payloads

Heartbeat payload:

```json
{
  "schema_version": 1,
  "user_id": "user-uuid-lowercase",
  "device_id": "device-uuid-lowercase",
  "status": "online",
  "source": "daemon-do",
  "sent_at_ms": 1739030400000,
  "seq": 42,
  "ttl_ms": 12000
}
```

Stream event payload:

```json
{
  "schema_version": 1,
  "user_id": "user-uuid-lowercase",
  "device_id": "device-uuid-lowercase",
  "status": "online",
  "source": "daemon-do",
  "sent_at_ms": 1739030400000,
  "seq": 42,
  "ttl_ms": 12000
}
```

## Environment

| Variable | Purpose |
| --- | --- |
| `PRESENCE_DO_TOKEN_SIGNING_KEY` | HMAC signing key for presence stream tokens. |
| `PRESENCE_DO_INGEST_TOKEN` | Bearer token required for daemon heartbeat ingestion. |

## Local Development

```sh
cd packages/presence-do-worker
pnpm dev
```

## Tests

```sh
cd packages/presence-do-worker
pnpm test
```
