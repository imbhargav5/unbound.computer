# Runtime Capability Detector

Runtime Capability Detector is the daemon's **system dependency detector**. It checks whether required tools are available on the host machine and returns a JSON-serializable status payload for IPC.

## Core Purpose

- Run dependency checks through the user's login shell (so PATH matches `.zprofile` / `.zshrc`).
- Report whether required binaries exist, plus their resolved paths.
- Keep the API pure, async, and easy to embed in daemon handlers.

## Dependency Checks

| Dependency | Required | Notes |
|---|---|---|
| `claude` | Yes | Claude Code CLI is mandatory for local sessions |
| `gh` | No | Optional, used for GitHub PR workflows (GH CLI Ops) |

## API

```rust
use runtime_capability_detector::{check_all, check_dependency, collect_capabilities};

let claude = check_dependency("claude").await?;
let status = check_all().await?;
let capabilities = collect_capabilities().await?;
```

## Behavior

- Each check runs `/bin/zsh -l -c "which <name>"` so the login shell is used.
- Successful checks return `DependencyInfo` with `installed=true` and a resolved path.
- Missing tools still return a `DependencyInfo` (with `installed=false`), not an error.

## Capabilities Payload

`collect_capabilities` builds the canonical payload synced to Supabase. It includes
the dependency status plus extra CLI tool discovery:

| Tool | Notes |
|---|---|
| `claude` | Includes discovered model IDs when available |
| `gh` | CLI presence only |
| `codex` | CLI presence only |
| `ollama` | CLI presence only |

## Data Types

```rust
pub struct DependencyInfo {
    pub name: String,
    pub installed: bool,
    pub path: Option<String>,
}

pub struct DependencyCheckResult {
    pub claude: DependencyInfo,
    pub gh: DependencyInfo,
}

pub struct Capabilities {
    pub cli: CliCapabilities,
    pub metadata: CapabilitiesMetadata,
}
```

## Module Layout

```
src/
├── lib.rs         # public exports
├── operations.rs  # dependency checks
├── types.rs       # IPC-friendly structs
└── error.rs       # error wrapper
```

## Tests

```bash
cd apps/daemon
cargo test -p runtime-capability-detector
```
