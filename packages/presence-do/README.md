# presence-do

Durable Object presence contract for daemon availability.

## Contract (storage record)

```json
{
  "schema_version": 1,
  "user_id": "user-uuid-lowercase",
  "device_id": "device-uuid-lowercase",
  "status": "online|offline",
  "source": "daemon-do",
  "last_heartbeat_ms": 1739030400000,
  "last_offline_ms": null,
  "updated_at_ms": 1739030400000,
  "seq": 42,
  "ttl_ms": 12000
}
```

## Contract (stream event)

```json
{
  "schema_version": 1,
  "user_id": "user-uuid-lowercase",
  "device_id": "device-uuid-lowercase",
  "status": "online|offline",
  "source": "daemon-do",
  "sent_at_ms": 1739030400000,
  "seq": 42,
  "ttl_ms": 12000
}
```

## API surface

- `POST /api/v1/mobile/presence/token`
- `GET /api/v1/mobile/presence/stream?user_id=...`
- `POST /api/v1/daemon/presence/heartbeat` (or signed DO ingress)

## Error model

`unauthorized`, `forbidden`, `rate_limited`, `unavailable`, `invalid_payload`.
