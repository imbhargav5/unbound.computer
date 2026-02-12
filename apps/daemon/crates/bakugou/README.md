# Bakugou

Bakugou is the daemon-side **GitHub CLI orchestration crate** for pull request workflows.

It provides typed operations for `gh` command execution while keeping `piccolo` focused on Git/libgit2 operations.

## Purpose and Boundaries

### Bakugou owns

- `gh` process orchestration (`tokio::process::Command`)
- non-interactive environment setup
- timeout handling
- command output parsing and normalization
- stable machine-readable error taxonomy

### Piccolo owns

- local Git operations via libgit2
- staging/unstaging, diffs, commit logs, commit/push primitives

Bakugou does **not** replace Piccolo. It complements it for GitHub PR lifecycle actions.

## Architecture

```
┌───────────────────────────────────────────────────────────────────────────┐
│                                 daemon-bin                               │
│                                                                           │
│ IPC handler / Itachi runtime                                              │
│       │                                                                   │
│       ▼                                                                   │
│    bakugou::operations::*                                                 │
│       │                                                                   │
│       ├─► command_runner::GhCommandRunner (non-interactive env + timeout)
│       │        │                                                          │
│       │        ▼                                                          │
│       │      gh CLI                                                       │
│       │                                                                   │
│       └─► typed parsing + error normalization                             │
└───────────────────────────────────────────────────────────────────────────┘
```

## Supported Operations and `gh` Mapping

| Bakugou operation | Primary command | Follow-up command |
|---|---|---|
| `auth_status` | `gh auth status --json hosts` | none |
| `pr_create` | `gh pr create ...` | `gh pr view <url> --json ...` |
| `pr_view` | `gh pr view [selector] --json ...` | none |
| `pr_list` | `gh pr list --state ... --limit ... --json ...` | none |
| `pr_checks` | `gh pr checks [selector] --json ...` | none |
| `pr_merge` | `gh pr merge [selector] --<method> ...` | `gh pr view [selector] --json ...` |

## Public API

```rust
pub async fn auth_status(input: AuthStatusInput) -> Result<AuthStatusResult, BakugouError>;
pub async fn pr_create(working_dir: &Path, input: PrCreateInput) -> Result<PrCreateResult, BakugouError>;
pub async fn pr_view(working_dir: &Path, input: PrViewInput) -> Result<PullRequestDetail, BakugouError>;
pub async fn pr_list(working_dir: &Path, input: PrListInput) -> Result<PrListResult, BakugouError>;
pub async fn pr_checks(working_dir: &Path, input: PrChecksInput) -> Result<PrChecksResult, BakugouError>;
pub async fn pr_merge(working_dir: &Path, input: PrMergeInput) -> Result<PrMergeResult, BakugouError>;
```

All public input/output types are in `types.rs` and are `serde`-serializable for IPC usage.

## Error Model

`BakugouError::code()` returns stable machine codes:

- `gh_not_installed`
- `gh_not_authenticated`
- `invalid_repository`
- `invalid_params`
- `not_found`
- `command_failed`
- `timeout`
- `parse_error`

Daemon handlers map these codes to JSON-RPC error classes and preserve the machine code in `error.data.code`.

## Timeout and Non-Interactive Guarantees

### Timeouts

- 30 seconds: `auth_status`, `pr_view`, `pr_list`, `pr_checks`
- 60 seconds: `pr_create`, `pr_merge`

### Non-interactive environment

Every `gh` command is run with:

- `GH_PROMPT_DISABLED=1`
- `GH_PAGER=cat`
- `PAGER=cat`
- `NO_COLOR=1`
- `CLICOLOR=0`

`stdin` is set to null and stdout/stderr are captured.

## Binary Resolution Strategy

`gh` executable resolution order:

1. `GH_PATH` env var (if non-empty)
2. `/opt/homebrew/bin/gh`
3. `/usr/local/bin/gh`
4. `/usr/bin/gh`
5. fallback: `gh` from `PATH`

## Module Layout

```
src/
├── lib.rs            # public exports
├── types.rs          # public input/output contracts
├── operations.rs     # typed operation implementations
├── command_runner.rs # executable resolution + process execution
└── error.rs          # error taxonomy + machine codes
```

## Integration Points

### Daemon IPC

`daemon-bin/src/ipc/handlers/gh.rs` invokes Bakugou operations and maps errors into IPC responses.

### Itachi Remote Commands

`daemon-bin/src/itachi/runtime.rs` routes `gh.pr.*.v1` remote commands to shared GH core functions backed by Bakugou.

## Testing Strategy

### Unit tests in this crate

- parser mappings for auth/PR/check payloads
- URL extraction for `pr_create`
- check summary bucket classification
- command error classification heuristics

### Commands

```bash
cd apps/daemon
cargo test -p bakugou
```

Recommended companion checks:

```bash
cargo test -p one-for-all-protocol
cargo test -p daemon-bin
```

## Known Limitations

- `pr_create`/`pr_merge` rely on follow-up `pr_view` for canonical output shape.
- Error classification uses stderr/stdout heuristics from gh messaging.
- CLI output schema changes in future gh versions may require parser updates.

## Extension Guidance

When adding new GitHub operations:

1. Add typed input/output in `types.rs`.
2. Implement operation in `operations.rs` using `GhCommandRunner`.
3. Extend error mapping only with backward-compatible machine codes.
4. Update crate README operation matrix and daemon protocol docs.
