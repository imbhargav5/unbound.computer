# presence-do-worker

Cloudflare Worker + Durable Object that manages per-user device presence state. Receives heartbeats from the daemon (via the web app proxy) and streams presence updates to mobile clients via SSE.

## Setup

```bash
npm install
npx wrangler login
```

### Secrets

Generate and set the required secrets:

```bash
openssl rand -base64 32  # PRESENCE_DO_TOKEN_SIGNING_KEY
openssl rand -hex 32     # PRESENCE_DO_INGEST_TOKEN

npx wrangler secret put PRESENCE_DO_TOKEN_SIGNING_KEY
npx wrangler secret put PRESENCE_DO_INGEST_TOKEN
```

### Deploy

```bash
npm run deploy
```

The worker deploys to `https://unbound-presence-do.<subdomain>.workers.dev`.

## Environment Variables

| Variable | Source | Description |
|----------|--------|-------------|
| `PRESENCE_DO_TOKEN_SIGNING_KEY` | Secret | HMAC-SHA256 key for signing/verifying presence stream tokens |
| `PRESENCE_DO_INGEST_TOKEN` | Secret | Bearer token for authenticating daemon heartbeat ingestion |
| `ENVIRONMENT` | `wrangler.toml` | Set to `"production"` to disable debug endpoint |

## Endpoints

### POST `/api/v1/daemon/presence/heartbeat`

Ingests a heartbeat from the daemon. Authenticated via `Authorization: Bearer <PRESENCE_DO_INGEST_TOKEN>`.

**Request body:**

```json
{
  "schema_version": 1,
  "user_id": "uuid",
  "device_id": "uuid",
  "status": "online" | "offline",
  "source": "daemon-do",
  "sent_at_ms": 1739030400000,
  "seq": 1,
  "ttl_ms": 12000
}
```

**Responses:**
- `204` — Heartbeat accepted
- `400` — Invalid payload (see `details` field)
- `401` — Invalid or missing bearer token
- `409` — Non-monotonic sequence number

### GET `/api/v1/mobile/presence/stream`

SSE stream of presence updates for a user. Authenticated via a signed presence token.

**Query params:** `?user_id=<uuid>`

**Headers:** `Authorization: Bearer <signed-presence-token>`

**Response:** `text/event-stream` with `data: <PresencePayload>` events.

### GET `/debug/presence`

Returns the full contents of a user's Durable Object storage. Disabled when `ENVIRONMENT=production`.

**Query params:** `?user_id=<uuid>`

**Example:**

```bash
curl -s "https://unbound-presence-do.<subdomain>.workers.dev/debug/presence?user_id=<uuid>" | jq
```

**Response:**

```json
{
  "active_streams": 0,
  "alarm": "2026-02-18T00:00:12.000Z",
  "records": {
    "device:<device-uuid>": {
      "schema_version": 1,
      "user_id": "<uuid>",
      "device_id": "<device-uuid>",
      "status": "online",
      "source": "daemon-do",
      "sent_at_ms": 1739030400000,
      "seq": 5,
      "ttl_ms": 12000,
      "last_heartbeat_ms": 1739030400000,
      "last_offline_ms": null,
      "updated_at_ms": 1739030400123
    }
  }
}
```

## Architecture

Each user gets their own Durable Object instance (keyed by `user_id`). The DO:

1. Stores per-device presence records in KV storage
2. Broadcasts updates to connected SSE streams
3. Sets alarms to auto-mark devices as `"offline"` when heartbeats stop (after `ttl_ms`)

### Request flow

```
daemon-ably -> web app proxy -> worker -> Durable Object
                                              |
mobile client <--- SSE stream ----------------+
```

## Development

```bash
npx wrangler dev    # Run locally
npx wrangler tail   # Stream live logs from deployed worker
```
