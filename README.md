# Unbound

A local-first AI coding assistant with a Tauri desktop client, native iOS app, and a background daemon.

## What is Unbound?

Unbound pairs a background Rust daemon with a Tauri desktop app, a native iOS app, and CLI tooling to provide AI-assisted coding sessions over a local Unix socket. The daemon manages Claude CLI and terminal processes, tracks sessions in SQLite, performs git operations, and exposes a board/task domain for company-agent-project-issue workflows.

The current daemon runtime is local-first and local-only: state is persisted in local SQLite plus platform secure storage, and clients interact through IPC methods and streaming events.

## Architecture

```
Desktop App (Tauri) ─┐
                     ├── Unix Socket (NDJSON) ──> Daemon (Rust)
CLI (Rust/ratatui) ──┘                              |
                                          ┌──────────┼───────────┐
                                       SQLite     Secure Storage  Local FS
                                       (state)    (keys/secrets) (repos/files)
                                          |
                                    ┌─────┼──────┐
                                 Claude  libgit2  GH CLI
                                  CLI    (git)   (optional)
```

Production desktop builds do not bundle the daemon. The desktop app connects to a separately installed `unbound-daemon`, can start an installed daemon when needed, and blocks on explicit install/update states when the daemon is missing or incompatible.

Clients connect to the daemon over a Unix domain socket using an NDJSON-based protocol. The daemon spawns and manages local processes, persists session/board state to SQLite, and streams runtime events to subscribers:

- **Request/response IPC:** structured method calls for board, session, repository, Claude, terminal, git, and system operations.
- **Streaming IPC:** `session.subscribe` channels with ordered events (message/status/terminal/Claude/session lifecycle).
- **Shared local identity:** device identifiers and key material are managed through secure local storage and reused across daemon runs.

## Project Structure

```
unbound.computer/
├── apps/
│   ├── daemon/          # Rust daemon (21 crates)
│   ├── desktop/         # Tauri desktop app (React + Rust)
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
| `daemon-bin` | Binary entry point, startup/lifecycle wiring, IPC handler registration |
| `daemon-config-and-utils` | Shared config, paths, logging/telemetry, crypto helpers |
| `daemon-ipc` | Unix socket IPC server/client, subscription transport |
| `daemon-database` | Async SQLite executor, migrations, query helpers |
| `daemon-storage` | Platform secure storage integration |
| `daemon-board` | Local board domain services (company/agent/project/issue/approval/workspace) |
| `agent-session-sqlite-persist-core` | SQLite-backed session engine with side-effects |
| `claude-process-manager` | Claude process orchestration and stream integration |
| `claude-debug-logs` | Raw Claude event JSONL debug logging |
| `git-ops` | Native git operations via libgit2 |
| `gh-cli-ops` | GitHub CLI orchestration for PR workflows |
| `session-title-generator` | Session title generation |
| `safe-repo-dir-lister` | Safe directory listing with traversal protection |
| `safe-file-ops` | Rope-backed file reader/writer with conflict detection |
| `ipc-protocol-types` | Shared request/response/event protocol types |
| `workspace-resolver` | Workspace and path resolution helpers |
| `process-event-bridge` | Process event normalization/bridging primitives |
| `session-lifecycle-orchestrator` | Session lifecycle orchestration helpers |
| `device-identity-crypto` | Device identity and crypto coordination |
| `daemon-lifecycle` | Daemon lifecycle utilities |
| `runtime-capability-detector` | System dependency detection for required tools |

## Daemon Sidecars

The repository still includes Go sidecar packages for Ably transport flows:

| Sidecar | Language | Purpose |
|---------|----------|---------|
| **daemon-ably** | Go | Ably transport process exposing a local socket for companion sidecars. |
| **daemon-falco** | Go | Ably publisher sidecar. |
| **daemon-nagato** | Go | Ably consumer sidecar. |

These sidecars are documented in their package READMEs and are not part of the current default local daemon bootstrap path.

## Tech Stack

**Daemon (Rust)**
- Tokio async runtime
- SQLite via rusqlite (WAL mode, async executor)
- libgit2 via git2 crate
- ChaCha20-Poly1305 + X25519 encryption
- Unix domain sockets via interprocess
- clap for CLI, tracing for logging
- OpenTelemetry integration via shared observability crate

**Daemon Sidecars (Go)**
- Ably SDK for real-time pub/sub (via `daemon-ably`)
- Binary frame protocol over Unix domain sockets
- Stateless, crash-safe design

**Desktop App (Tauri)**
- React + Vite frontend
- Tauri v2 Rust shell for native integrations
- Unix socket IPC to daemon through a Rust bridge
- xterm.js for terminal rendering

**macOS App (Swift, legacy)**
- SwiftUI native client retained in-tree during desktop migration

**Web App (TypeScript)**
- Next.js (App Router)
- Supabase client for auth and data
- Sentry for error tracking
- Biome for linting/formatting

**Infrastructure**
- pnpm workspaces + Turborepo
- Apache-2.0 license

## Prerequisites

- **Rust** (stable toolchain)
- **Node.js** v20+
- **pnpm** v9+
- **Xcode Command Line Tools** (for macOS desktop builds)
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

### 6. Run the desktop app

```sh
# Start the daemon in the foreground
pnpm daemon:dev

# Or start the daemon and the Tauri desktop app together
pnpm daemon:dev:app
```

For production-style installs, build and install `unbound-daemon` separately from the desktop app. The desktop shell will refuse to continue until it finds a compatible installed daemon.

### 7. Start SigNoz locally (optional)

Unbound's local observability defaults assume:

- OTLP HTTP collector on `http://localhost:4318`
- SigNoz UI available locally at `http://localhost:3301`

The canonical local SigNoz checkout is:

```sh
~/Code/signoz
```

If you do not already have a local SigNoz stack there, install it with:

```sh
git clone -b main https://github.com/SigNoz/signoz.git "$HOME/Code/signoz"
```

Manage it from this repo with:

```sh
pnpm signoz:start
pnpm signoz:status
pnpm signoz:stop
```

These commands wrap the Docker Compose stack under `~/Code/signoz/deploy/docker`.

Then open `http://localhost:3301` and verify that the collector is reachable on `http://localhost:4318`.

To validate that this repo is actually sending logs and traces into SigNoz, run:

```sh
EXPECTED_SERVICES=daemon,macos REQUIRE_TRACES=1 ./scripts/ci/signoz-smoke.sh 1800
```

For the observability model and investigation workflow used in this repo, see `packages/observability/SIGNOZ_OPERATING_MODEL.md`.

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
# Lint TypeScript and JavaScript
pnpm oxlint

# Format code
pnpm oxfmt:write

# Check formatting
pnpm oxfmt

# Rust
cd apps/daemon && cargo clippy
```

## License

Apache-2.0 -- see [LICENSE](LICENSE) for details.
