# daemon-ipc

Unix domain socket IPC transport for daemon request/response calls and
session event streaming.

## Purpose

`daemon-ipc` provides the runtime transport layer used by local clients
(macOS app, CLI, tests) to communicate with the daemon.

## Components

- `IpcServer`
  - binds a Unix socket
  - dispatches request handlers by `Method`
  - supports request/response and streaming subscription flows
- `SubscriptionManager`
  - per-session broadcast channels
  - global broadcast channel for non-session events
- `IpcClient`
  - typed request helpers (`call_method`, `call_method_with_params`)
  - `subscribe(session_id)` for streaming events
- `StreamingSubscription`
  - `recv()` loop for event delivery
  - `unsubscribe()` to close cleanly

## Protocol

Wire format is NDJSON:

- one JSON object per line
- methods and payload schemas defined in `ipc-protocol-types`

Streaming flow:

1. client sends `session.subscribe` with `session_id`
2. server replies success
3. optional initial state events are sent (if registered)
4. server streams events until client unsubscribes or disconnects

## Trace Context Propagation

The server extracts optional W3C trace context from incoming requests and sets
it as the request span parent. Client-side calls also attach current trace
context when available.

Events can carry trace context so clients can continue the same trace chain.

## Error Handling

Common transport/runtime errors are surfaced via `IpcError`:

- socket/connect failures
- parse/serialization failures
- protocol violations
- closed connections

Method-level failures are encoded as structured `Response::error(...)` values.
