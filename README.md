# Unbound

A local-first AI coding assistant with native clients, a background daemon, and optional cloud sync.

## What is Unbound?

Unbound is a development tool that pairs a background Rust daemon with native client applications to provide AI-assisted coding sessions. The daemon manages Claude CLI processes, tracks sessions in a local SQLite database, handles authentication, and orchestrates git operations -- all through a Unix socket IPC interface that any client can connect to.

The system follows a local-first architecture: all session data lives in SQLite on your machine, and the daemon operates fully offline. When signed in, sessions optionally sync to Supabase with end-to-end encryption (X25519 + ChaCha20-Poly1305), enabling cross-device access through the web app.

Real-time streaming uses a dual-path sync model: **Ably** serves as the hot path for instant message delivery (via the Falco sidecar through `daemon-ably`), while **Supabase** serves as the cold path for durable, batched message sync (via the Levi worker). Inbound remote commands (e.g., web-initiated sessions) flow through Ably into the Nagato sidecar (also through `daemon-ably`), which forwards them to the daemon for processing.

## Architecture

```
macOS App (SwiftUI) ──┐
                      ├── Unix Socket (NDJSON) ──> Daemon (Rust)
CLI (Rust/ratatui) ───┘                              |
                                          ┌──────────┼──────────┐
                                       SQLite      Supabase     Ably
                                       (local)   (cold sync)  (hot sync)
                                          |
                                    ┌─────┼──────┐
                                 Claude  libgit2  Groq
                                  CLI    (git)   (titles)

                          ┌────────── Daemon Sidecars ──────────┐
                          │                                     │
                   daemon-ably (Go)                       Nagato (Go)
                 Ably transport + IPC               Consumes remote
                        for sidecars                commands from Ably
                          │                                     │
                        Falco (Go)                              │
                  Publishes state changes to Ably               │
```

Clients connect to the daemon over a Unix domain socket using an NDJSON-based protocol. The daemon spawns and manages Claude CLI processes, persists all session data to SQLite, and syncs encrypted messages through two paths:

- **Hot path (Ably via Falco):** Every message is published to Ably in real-time for instant cross-device delivery. Falco is a Go sidecar that receives side-effects from the daemon over a Unix socket and publishes them to Ably channels.
- **Cold path (Supabase via Levi):** Messages are batched, encrypted, and upserted to Supabase for durable storage and offline sync. Levi is a Rust worker with cursor-based sync, batching (50 messages / 500ms), and exponential backoff retries.
- **Inbound commands (Ably via Nagato):** Remote commands (e.g., starting a session from the web) arrive on Ably, are consumed by the Nagato Go sidecar, and forwarded to the daemon over a Unix socket.

## Project Structure

```
unbound.computer/
├── apps/
│   ├── daemon/          # Rust daemon (23 crates)
│   ├── macos/           # macOS native app (SwiftUI)
│   ├── cli-new/         # Terminal client (Rust/ratatui)
│   ├── web/             # Web app (Next.js)
│   ├── database/        # Supabase schema and migrations
│   ├── email/           # Transactional email templates
│   └── ios/             # iOS app (placeholder)
├── packages/
│   ├── daemon-ably/     # Ably transport sidecar (Go)
│   ├── daemon-ably-client/ # daemon-ably IPC client (Go)
│   ├── daemon-falco/    # Ably publisher sidecar (Go)
│   ├── daemon-nagato/   # Ably consumer sidecar (Go)
│   ├── protocol/        # Shared message protocol types
│   ├── crypto/          # E2E encryption (TypeScript)
│   ├── session/         # Session management helpers
│   ├── transport-reliability/  # Reliable message delivery
│   ├── observability/   # Shared logging (Rust + TS)
│   ├── presence-do/     # Durable Object presence contract
│   ├── presence-do-worker/ # Presence DO ingress + SSE worker
│   ├── agent-runtime/   # Agent execution runtime
│   ├── git-worktree/    # Git worktree utilities
│   ├── redis/           # Redis helpers (Upstash + ioredis)
│   ├── web-session/     # Web session management
│   └── typescript-config/ # Shared TS config
├── supabase/            # Supabase project configuration
├── docs/                # Internal documentation
└── scripts/             # Build and release scripts
```

## Daemon Crates

The Rust daemon is organized into focused crates under `apps/daemon/crates/`:

| Crate | Description |
|-------|-------------|
| `daemon-bin` | Binary entry point, CLI parsing, daemon lifecycle, IPC handlers |
| `daemon-config-and-utils` | Shared config, paths, logging, hybrid encryption |
| `daemon-ipc` | Unix socket server, NDJSON protocol, request routing |
| `daemon-auth` | Backward-compat shim for `ymir` |
| `daemon-database` | Async SQLite executor, migrations, model types |
| `daemon-storage` | Platform-specific secure storage (Keychain, Secret Service, Credential Vault) |
| `armin` | SQLite-backed session engine: commits facts, derives views, emits side-effects |
| `deku` | Claude CLI process manager: spawning, streaming, event parsing |
| `piccolo` | Native git operations via libgit2 (status, diff, log, branches, worktrees) |
| `bakugou` | GitHub CLI orchestration for PR workflows |
| `levi` | Supabase message sync worker with batching, encryption, and retries |
| `toshinori` | Supabase + Ably sync sink for Armin side-effects |
| `yamcha` | Session title generation via Groq Llama 3.1 8B |
| `yagami` | Safe directory listing with path traversal protection |
| `ymir` | Auth FSM, OAuth flows, Supabase integration |
| `gyomei` | Rope-backed file reader/writer with conflict detection |
| `rengoku-sessions` | Session lifecycle orchestration |
| `eren-machines` | Process lifecycle management |
| `sakura-working-dir-resolution` | Workspace path resolution |
| `one-for-all-protocol` | Shared protocol types (extracted from daemon-ipc) |
| `sasuke-crypto` | Device identity and crypto coordination |
| `historia-lifecycle` | Daemon lifecycle and startup orchestration |
| `tien` | System dependency detection for required CLI tools |

## Daemon Sidecars

The daemon communicates with Go sidecar processes over Unix domain sockets using a custom binary frame protocol:

| Sidecar | Language | Purpose |
|---------|----------|---------|
| **daemon-ably** | Go | Owns the Ably realtime connection and exposes an IPC transport socket for Falco/Nagato. |
| **Falco** | Go | Publishes Armin side-effects (messages, session events) to Ably channels for real-time cross-device sync. Implements at-least-once delivery with retry. |
| **Nagato** | Go | Subscribes to Ably for inbound remote commands and forwards them to the daemon. Implements fail-open timeouts (15s) to prevent blocking. |

Both sidecars are stateless and crash-safe -- the daemon tracks unacknowledged effects for resend on restart, and Ably handles redelivery for unprocessed commands.

The daemon also captures sidecar stdout/stderr streams and forwards them through the observability pipeline for unified log search.

## Tech Stack

**Daemon (Rust)**
- Tokio async runtime
- SQLite via rusqlite (WAL mode, async executor)
- libgit2 via git2 crate
- ChaCha20-Poly1305 + X25519 encryption
- Unix domain sockets via interprocess
- clap for CLI, tracing for logging
- PostHog + Sentry sinks via shared observability crate

**Daemon Sidecars (Go)**
- Ably SDK for real-time pub/sub (via `daemon-ably`)
- Binary frame protocol over Unix domain sockets
- Stateless, crash-safe design

**macOS App (Swift)**
- SwiftUI with MVVM architecture
- Unix socket IPC to daemon
- swift-log for structured logging
- Keychain integration for secure storage

**Web App (TypeScript)**
- Next.js (App Router)
- Supabase client for auth and data
- Sentry for error tracking
- Biome for linting/formatting

**Infrastructure**
- Supabase (Postgres, Auth, Realtime)
- Ably (real-time message delivery, remote command routing)
- pnpm workspaces + Turborepo
- AGPL-3.0 license

## Prerequisites

- **Rust** (stable toolchain)
- **Node.js** v20+
- **pnpm** v9+
- **Xcode** (for macOS app)
- **Supabase CLI** (for local database development)

## Getting Started

### 1. Install dependencies

```sh
pnpm install
```

### 2. Build the daemon

```sh
cd apps/daemon && cargo build --release
```

Or from the repo root:

```sh
pnpm daemon:build
```

### 3. Run the daemon

```sh
# Background mode
pnpm daemon:start

# Foreground with debug logging
pnpm daemon:foreground

# Check status
pnpm daemon:status

# Stop
pnpm daemon:stop
```

### 4. Build and run the CLI

```sh
pnpm cli:build
pnpm cli
```

### 5. Run the web app

```sh
pnpm web#dev
```

### 6. Open the macOS app

Open `apps/macos/unbound-macos.xcodeproj` in Xcode and build/run.

## Development

### Daemon

```sh
cd apps/daemon

# Build
cargo build

# Run tests
cargo test

# Run with trace logging
RUST_LOG=trace cargo run -- start --foreground
```

### Web App

```sh
cd apps/web
cp .env.local.example .env.local  # Configure environment
pnpm dev
```

### Database

```sh
cd apps/database
pnpm supabase start   # Start local Supabase
pnpm supabase db push # Apply migrations
```

### Code Quality

```sh
# Lint and format (TypeScript/JavaScript)
npx ultracite fix

# Check for issues
npx ultracite check

# Rust
cd apps/daemon && cargo clippy
```

## License

AGPL-3.0 -- see [LICENSE](LICENSE) for details.
