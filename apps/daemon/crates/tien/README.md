# Tien

Tien is the daemon's **system dependency detector**. It checks whether required tools are available on the host machine and returns a JSON-serializable status payload for IPC.

## Core Purpose

- Run dependency checks through the user's login shell (so PATH matches `.zprofile` / `.zshrc`).
- Report whether required binaries exist, plus their resolved paths.
- Keep the API pure, async, and easy to embed in daemon handlers.

## Current Checks

| Dependency | Required | Notes |
|---|---|---|
| `claude` | Yes | Claude Code CLI is mandatory for local sessions |
| `gh` | No | Optional, used for GitHub PR workflows (Bakugou) |

## API

```rust
use tien::{check_all, check_dependency};

let claude = check_dependency("claude").await?;
let status = check_all().await?;
```

## Behavior

- Each check runs `/bin/zsh -l -c "which <name>"` so the login shell is used.
- Successful checks return `DependencyInfo` with `installed=true` and a resolved path.
- Missing tools still return a `DependencyInfo` (with `installed=false`), not an error.

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
cargo test -p tien
```
