# daemon-stream

High-performance shared memory streaming for low-latency IPC.

## Purpose

Provides zero-copy, sub-microsecond event streaming between daemon and clients. Used for latency-sensitive operations like Claude CLI output and terminal streaming.

## Key Features

- **Shared memory ring buffer**: Lock-free SPSC queue
- **Zero-copy reads**: No serialization on hot path
- **~1-5µs latency**: 10-100x faster than Unix sockets
- **Fallback support**: Degrades to socket transport if unavailable

## How It Differs From daemon-ipc

| daemon-stream | daemon-ipc |
|---------------|------------|
| Shared memory | Unix socket |
| ~1-5µs latency | ~35-130µs latency |
| Streaming only | Request/response + streaming |
| Zero-copy binary | JSON serialization |

Use **stream** for high-frequency events (terminal output). Use **ipc** for RPC and subscriptions.
