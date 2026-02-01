# daemon-outbox

Transactional outbox pattern for reliable event delivery to the relay server.

## Purpose

Guarantees message delivery even through crashes and network failures. Events are persisted to SQLite before sending, ensuring no data loss.

## Key Features

- **Crash recovery**: Resumes pending events after restart
- **Batching**: Groups events (up to 50) for efficient delivery
- **Retry with backoff**: Exponential backoff on failures
- **Per-session queues**: Isolated queues prevent cross-session blocking

## How It Differs From daemon-relay

| daemon-outbox | daemon-relay |
|---------------|--------------|
| HTTP POST to relay API | WebSocket connection |
| Guaranteed delivery | Best-effort delivery |
| Persistent queue (SQLite) | In-memory only |
| Async background processing | Real-time streaming |

Use **outbox** for critical messages (chat, tool calls). Use **relay** for real-time events (typing, presence).
