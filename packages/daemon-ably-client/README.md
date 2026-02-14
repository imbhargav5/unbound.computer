# daemon-ably-client

Go client library for the daemon-managed Ably transport (`daemon-ably`). It speaks NDJSON over a Unix domain socket and provides publish + subscribe primitives with reconnect handling.

## Core Purpose

- Keep **Falco** and **Nagato** free of direct Ably SDK usage
- Centralize IPC framing and ACK handling for `daemon-ably`
- Restore subscriptions after reconnects

## Supported Operations

| Operation | Direction | Description |
|---|---|---|
| `publish.v1` | client → daemon-ably | Publish payloads (Falco path) |
| `publish.ack.v1` | client → daemon-ably | Publish ACKs (Nagato path) |
| `subscribe.v1` | client → daemon-ably | Subscribe to a channel/event |
| `message.v1` | daemon-ably → client | Push inbound messages |

## API Overview

```go
client, err := client.New("/Users/me/.unbound/ably.sock")
if err != nil { /* ... */ }

defer client.Close()
ctx := context.Background()

if err := client.Connect(ctx); err != nil { /* ... */ }
if err := client.Publish(ctx, "session:1:conversation", "conversation.message.v1", payload, 5*time.Second); err != nil { /* ... */ }

if err := client.Subscribe(ctx, client.Subscription{
  SubscriptionID: "nagato-primary",
  Channel: "remote:device-id:commands",
  Event: "remote.command.v1",
}); err != nil { /* ... */ }

for msg := range client.Messages() {
  // msg.Payload is raw bytes
}
```

## Reconnect Semantics

- `Client` auto-reconnects with exponential backoff (max 3s).
- Active subscriptions are replayed after reconnect.
- In-flight requests are failed fast on disconnect.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `DAEMON_ABLY_MAX_FRAME_BYTES` | `2097152` | Maximum NDJSON frame size accepted from daemon-ably |

## Package Layout

```
packages/daemon-ably-client/
├── client/
│   ├── client.go        # NDJSON client + reconnect
│   └── client_test.go   # ack + reconnect tests
├── go.mod
└── README.md
```

## Development

```bash
cd packages/daemon-ably-client
go test ./...
```
