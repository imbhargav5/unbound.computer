# Piccolo

**Native git operations for the Unbound daemon using libgit2.**

Piccolo provides fast, reliable git integration without shelling out to the git CLI. It encapsulates all git operations required for repository status, diffs, commit history, branch management, and worktree operations.

## Overview

The crate exposes pure functions that operate on repository paths. All operations are synchronous and designed for use within the daemon's IPC handlers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           Daemon                                 │
│                                                                  │
│  IPC Handler ──► piccolo::get_status() ──► GitStatusResult      │
│       │                                                          │
│       ├──────► piccolo::get_file_diff() ──► GitDiffResult       │
│       │                                                          │
│       ├──────► piccolo::get_log() ──► GitLogResult              │
│       │                                                          │
│       ├──────► piccolo::get_branches() ──► GitBranchesResult    │
│       │                                                          │
│       ├──────► piccolo::stage_files() ──► ()                    │
│       │                                                          │
│       └──────► piccolo::create_worktree() ──► String (path)     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        libgit2 (git2-rs)                         │
│                                                                  │
│  Repository, Index, Status, Diff, Revwalk, Worktree             │
└─────────────────────────────────────────────────────────────────┘
```

## Operations

| Function | Description | IPC Method |
|----------|-------------|------------|
| `get_status` | Query working tree and index status | `git.status` |
| `get_file_diff` | Generate unified diff for a file | `git.diff_file` |
| `get_log` | Retrieve commit history with pagination | `git.log` |
| `get_branches` | List all local and remote branches | `git.branches` |
| `stage_files` | Add files to the index | `git.stage` |
| `unstage_files` | Remove files from the index | `git.unstage` |
| `discard_changes` | Reset working tree changes | `git.discard` |
| `create_worktree` | Create a linked worktree (default root) | - |
| `create_worktree_with_options` | Create a linked worktree with root/base/branch options | - |
| `remove_worktree` | Remove a linked worktree | - |

## Usage

### Repository Status

```rust
use piccolo::get_status;
use std::path::Path;

let status = get_status(Path::new("/path/to/repo"))?;

println!("Branch: {:?}", status.branch);
println!("Clean: {}", status.is_clean);

for file in &status.files {
    let state = if file.staged { "staged" } else { "unstaged" };
    println!("  {} {:?} ({})", file.path, file.status, state);
}
```

### File Diff

```rust
use piccolo::get_file_diff;

let diff = get_file_diff(repo_path, "src/main.rs", Some(500))?;

if diff.is_binary {
    println!("Binary file");
} else {
    println!("+{} -{}", diff.additions, diff.deletions);
    if diff.is_truncated {
        println!("(truncated)");
    }
    println!("{}", diff.diff);
}
```

### Commit History

```rust
use piccolo::get_log;

// Get first 20 commits from HEAD
let log = get_log(repo_path, Some(20), None, None)?;

for commit in &log.commits {
    println!("{} {} - {}",
        commit.short_oid,
        commit.author_name,
        commit.summary
    );
}

// Pagination
if log.has_more {
    let page2 = get_log(repo_path, Some(20), Some(20), None)?;
}

// Specific branch
let feature_log = get_log(repo_path, Some(50), None, Some("feature/new-ui"))?;
```

### Branch Information

```rust
use piccolo::get_branches;

let branches = get_branches(repo_path)?;

println!("Current: {:?}", branches.current);

println!("Local branches:");
for branch in &branches.local {
    let current = if branch.is_current { "* " } else { "  " };
    let tracking = match &branch.upstream {
        Some(u) => format!(" [tracking {} +{} -{}]", u, branch.ahead, branch.behind),
        None => String::new(),
    };
    println!("{}{}{}", current, branch.name, tracking);
}

println!("Remote branches:");
for branch in &branches.remote {
    println!("  {}", branch.name);
}
```

### Staging Operations

```rust
use piccolo::{stage_files, unstage_files, discard_changes};

// Stage files
stage_files(repo_path, &["src/main.rs", "Cargo.toml"])?;

// Unstage files (keep working tree changes)
unstage_files(repo_path, &["src/main.rs"])?;

// Discard working tree changes (destructive!)
discard_changes(repo_path, &["src/experimental.rs"])?;
```

### Worktree Management

```rust
use piccolo::{create_worktree, create_worktree_with_options, remove_worktree};
use std::path::Path;

// Create a worktree for a session
let worktree_path = create_worktree(
    repo_path,
    "session-123",  // worktree name
    None,           // uses branch: unbound/session-123
)?;
// Created at (wrapper default): /path/to/repo/.unbound/worktrees/session-123/

// With explicit root/base/branch
let worktree_path = create_worktree_with_options(
    repo_path,
    "feature-work",
    Path::new("~/.unbound/repo-123/worktrees"),
    Some("origin/main"),
    Some("feature/my-feature"),
)?;

// Clean up worktree
remove_worktree(repo_path, Path::new(&worktree_path))?;
```

## Data Types

### GitStatusResult

```rust
pub struct GitStatusResult {
    pub files: Vec<GitStatusFile>,  // Changed files
    pub branch: Option<String>,     // Current branch (None if detached)
    pub is_clean: bool,             // No changes?
}

pub struct GitStatusFile {
    pub path: String,               // Relative to repo root
    pub status: GitFileStatus,      // Modified, Added, Deleted, etc.
    pub staged: bool,               // In index?
}
```

### GitFileStatus

```rust
pub enum GitFileStatus {
    Modified,    // Content changed
    Added,       // New file
    Deleted,     // File removed
    Renamed,     // File renamed
    Copied,      // File copied
    Untracked,   // Not in git
    Ignored,     // Matched by .gitignore
    Typechange,  // e.g., file → symlink
    Unreadable,  // Cannot read file
    Conflicted,  // Merge conflict
    Unchanged,   // No changes
}
```

### GitDiffResult

```rust
pub struct GitDiffResult {
    pub file_path: String,    // File being diffed
    pub diff: String,         // Unified diff content
    pub is_binary: bool,      // Binary file?
    pub is_truncated: bool,   // Hit max_lines limit?
    pub additions: u32,       // Lines added
    pub deletions: u32,       // Lines removed
}
```

### GitCommit

```rust
pub struct GitCommit {
    pub oid: String,           // Full SHA (40 chars)
    pub short_oid: String,     // Short SHA (7 chars)
    pub message: String,       // Full message
    pub summary: String,       // First line
    pub author_name: String,
    pub author_email: String,
    pub author_time: i64,      // Unix timestamp
    pub committer_name: String,
    pub committer_time: i64,
    pub parent_oids: Vec<String>,  // For graph visualization
}
```

### GitBranch

```rust
pub struct GitBranch {
    pub name: String,              // Branch name
    pub is_current: bool,          // Checked out?
    pub is_remote: bool,           // Remote-tracking?
    pub upstream: Option<String>,  // Tracking target
    pub ahead: u32,                // Commits ahead of upstream
    pub behind: u32,               // Commits behind upstream
    pub head_oid: String,          // Branch HEAD commit
}
```

## Worktree Layout

When creating worktrees, Piccolo uses this structure:

```
/path/to/repo/
├── .git/
├── .unbound/
│   └── worktrees/
│       ├── session-abc/
│       │   ├── .git           <- File pointing to main .git
│       │   ├── src/
│       │   └── Cargo.toml
│       └── session-xyz/
│           └── ...
├── src/
└── Cargo.toml
```

Each worktree gets its own branch (default: `unbound/<name>`).

## Error Handling

All operations return `Result<T, String>` with descriptive error messages:

```rust
match get_status(path) {
    Ok(status) => { /* use status */ }
    Err(e) => {
        // e.g., "Failed to open repository: ..."
        eprintln!("Git error: {}", e);
    }
}
```

Common errors:
- `Failed to open repository` - Not a git repo or permissions issue
- `Failed to find branch` - Branch doesn't exist
- `Failed to stage` - File doesn't exist or index error
- `Worktree already exists` - Name collision

## Testing

```bash
cargo test -p piccolo
```

Tests include:
- Status query on non-repo (error case)
- Status query on current repo
- Delta to status conversion
- Diff on non-existent file (error case)

## Why "Piccolo"?

Piccolo is a small woodwind instrument. Like its namesake, this crate is small, focused, and produces clear output from git repositories.
