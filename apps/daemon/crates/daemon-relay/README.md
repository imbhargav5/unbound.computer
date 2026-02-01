# daemon-relay

WebSocket client for real-time communication with the Unbound relay server.

## Purpose

Maintains a persistent WebSocket connection to the relay server for real-time bi-directional messaging between devices. Handles session subscriptions, authentication, and connection lifecycle.

## Key Features

- **Auto-reconnect**: Exponential backoff reconnection on disconnect
- **Heartbeat**: Periodic keepalive to maintain connection
- **Session management**: Join/leave coding sessions
- **Event broadcasting**: Receives and emits relay events

## How It Differs From daemon-outbox

| daemon-relay | daemon-outbox |
|--------------|---------------|
| Real-time WebSocket connection | HTTP-based delivery |
| Bi-directional messaging | One-way (daemon → server) |
| Ephemeral (connection-based) | Persistent (SQLite-backed) |
| Session subscriptions | Message queue with batching |

Use **relay** for real-time presence and session events. Use **outbox** for guaranteed message delivery.
