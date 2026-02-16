# daemon-ably

`daemon-ably` is the daemon-managed Ably transport sidecar used by both Falco (egress) and Nagato (ingress).

It centralizes:

- Ably connectivity and reconnect behavior
- audience-scoped broker token usage (`daemon_falco`, `daemon_nagato`)
- local IPC transport for sidecars on `~/.unbound/ably.sock`
- message-based daemon heartbeat stream for iOS availability gating

## Core Purpose

> One local Ably transport, shared by all daemon sidecars.

Falco and Nagato no longer create their own Ably SDK clients. They use `daemon-ably-client` over a Unix socket while `daemon-ably` owns realtime sessions and subscription restore behavior.

## Architecture

```text
┌──────────────────────────────────────────────────────────────────────┐
│                         unbound-daemon                               │
│                                                                      │
│  starts token broker (~/.unbound/ably-auth.sock)                    │
│  starts daemon-ably (~/.unbound/ably.sock)                           │
└──────────────────────────────────────────────────────────────────────┘
                │
                │ local IPC (`UNBOUND_ABLY_SOCKET`)
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                           daemon-ably                                │
│                                                                      │
│  Falco client (publish/heartbeat)         Nagato client (subscribe/ack) │
│  audience: daemon_falco                   audience: daemon_nagato    │
│                                                                      │
│  IPC ops: publish.v1, publish.ack.v1, subscribe.v1, message.v1      │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
                │
                │ Ably Realtime
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                               Ably                                   │
└──────────────────────────────────────────────────────────────────────┘
```

## Heartbeat Contract

`daemon-ably` publishes daemon availability as a message stream (not native Ably Presence API).

| Field | Value |
|-------|-------|
| Channel | `presence:{user_id}` (normalized to lowercase) |
| Event | `daemon.presence.v1` |
| Source | `daemon-ably` |
| Status values | `online`, `offline` |
| Behavior | Publish immediate `online`, then periodic `online`; best-effort `offline` on graceful shutdown |

Payload schema:

```json
{
  "schema_version": 1,
  "user_id": "user-uuid",
  "device_id": "device-uuid",
  "status": "online",
  "source": "daemon-ably",
  "sent_at_ms": 1739030400000
}
```

`user_id` is normalized by trimming whitespace and lowercasing before being used
in the channel name and payload, so consumers should treat it as lowercase.

## Local IPC Protocol (NDJSON)

All messages are newline-delimited JSON frames over Unix domain socket.

### Requests

| `op` | Purpose |
|------|---------|
| `publish.v1` | Publish using Falco transport client |
| `publish.ack.v1` | Publish using Nagato transport client (ACK path) |
| `subscribe.v1` | Register channel/event subscription |

### Responses / Push

| `op` | Purpose |
|------|---------|
| `publish.ack.v1` | Acknowledges `publish.v1` and `publish.ack.v1` requests |
| `subscribe.ack.v1` | Acknowledges `subscribe.v1` requests |
| `message.v1` | Server push for subscribed Ably messages |

### Example Frames

Publish request:

```json
{
  "op": "publish.v1",
  "request_id": "uuid",
  "channel": "session:123:conversation",
  "event": "conversation.message.v1",
  "payload_b64": "eyJzY2hlbWFfdmVyc2lvbiI6MX0=",
  "timeout_ms": 5000
}
```

Subscription request:

```json
{
  "op": "subscribe.v1",
  "request_id": "uuid",
  "subscription_id": "nagato",
  "channel": "remote:device-uuid:commands",
  "event": "remote.command.v1"
}
```

Inbound push frame:

```json
{
  "op": "message.v1",
  "subscription_id": "nagato",
  "message_id": "ably-msg-id",
  "channel": "remote:device-uuid:commands",
  "event": "remote.command.v1",
  "payload_b64": "AAEC",
  "received_at_ms": 1739030400000
}
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `UNBOUND_ABLY_SOCKET` | `~/.unbound/ably.sock` | Local IPC socket path |
| `UNBOUND_ABLY_BROKER_SOCKET` | (required) | Broker socket path from daemon (`~/.unbound/ably-auth.sock`) |
| `UNBOUND_ABLY_BROKER_TOKEN_FALCO` | (required) | Audience token used by Falco publish client |
| `UNBOUND_ABLY_BROKER_TOKEN_NAGATO` | (required) | Audience token used by Nagato subscribe/ack client |
| `DAEMON_ABLY_MAX_FRAME_BYTES` | `2097152` | Maximum NDJSON frame size accepted on IPC socket |
| `DAEMON_ABLY_HEARTBEAT_INTERVAL` | `5` | Heartbeat interval in seconds |
| `DAEMON_ABLY_PUBLISH_TIMEOUT` | `5` | Publish/subscribe timeout in seconds |
| `DAEMON_ABLY_SHUTDOWN_TIMEOUT` | `2` | Graceful shutdown timeout in seconds |
| `UNBOUND_BASE_DIR` | `$HOME/.unbound` | Base dir for default socket path resolution |

CLI flags:

- `--device-id` (required)
- `--user-id` (required)
- `--debug` (optional)

## Package Structure

```text
packages/daemon-ably/
├── cmd/daemon-ably/main.go  # Process entrypoint
├── config/config.go         # Env/flag config and validation
├── runtime/broker.go        # Ably auth callback via broker socket
├── runtime/runtime.go       # Ably manager + heartbeat + subscriptions
├── runtime/server.go        # NDJSON IPC server
├── go.mod
├── go.sum
└── README.md
```

## Regression Matrix

| Scenario | Expected Result |
|----------|-----------------|
| Falco publish through `publish.v1` | Side-effects are acknowledged and egress reaches Ably |
| Nagato subscribe through `subscribe.v1` | `message.v1` frames are delivered for `remote.command.v1` |
| ACK publish through `publish.ack.v1` | `remote.command.ack.v1` publishes succeed via Nagato audience |
| Ably reconnect while process stays alive | daemon-ably reconnects and restores active subscriptions |
| malformed NDJSON frame | request is rejected, connection remains usable |
| oversized NDJSON frame | connection closes and logs max-frame violation |
| graceful shutdown | sidecar attempts offline heartbeat and removes `ably.sock` |
