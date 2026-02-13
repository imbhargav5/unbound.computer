# @unbound/agent-runtime

Agent runtime primitives for running Claude sessions with structured state, encryption, and queueing.

This package is used by clients and services that need to spawn Claude processes, manage session state transitions, and handle encrypted message flow.

## What It Provides

- **Claude process wrapper** with structured stream events
- **Session lifecycle** state machine (`pending` → `active` → `paused` → `ended`)
- **Session manager** for multi-session orchestration
- **Message queue** with ordering, retry, and acks
- **Session encryption** helpers for payload protection

## Primary Exports

| Export | Purpose |
|---|---|
| `ClaudeProcess` / `createClaudeProcess` | Spawn and stream Claude CLI output |
| `Session` / `createSession` | State-aware session wrapper |
| `SessionManager` / `createSessionManager` | Manage multiple sessions |
| `MessageQueue` / `createMessageQueue` | Ordered, ackable message queue |
| `EncryptionManager` / `SessionEncryption` | Encrypt/decrypt session messages |
| `PairwiseEncryptionManager` | Pairwise device session encryption |

## Example

```ts
import {
  createSessionManager,
  createClaudeProcess,
  createSession,
  createMessageQueue,
} from "@unbound/agent-runtime";

const manager = createSessionManager({ maxConcurrent: 1 });
const queue = createMessageQueue({ maxInFlight: 8 });

const process = createClaudeProcess({
  cwd: process.cwd(),
  model: "claude-3-7-sonnet",
});

const session = createSession({
  id: crypto.randomUUID(),
  process,
  queue,
});

manager.register(session);
```

## Module Layout

```
src/
├── process.ts     # ClaudeProcess implementation
├── session.ts     # Session state machine
├── manager.ts     # SessionManager
├── queue.ts       # MessageQueue with acks
├── encryption.ts  # Session + pairwise encryption
└── types.ts       # Shared types + schemas
```

## Development

```bash
pnpm -C packages/agent-runtime build
pnpm -C packages/agent-runtime test
```
