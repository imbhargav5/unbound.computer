# SafeFileOps

**Secure rope-backed text file read/write utilities for the Unbound daemon.** SafeFileOps provides cached, revision-tracked file I/O with path traversal protection and atomic writes.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           Daemon                                 │
│                                                                  │
│  IPC Handler ──► SafeFileOps                                         │
│                    │                                             │
│                    ├── read_full()    ──► ReadFullResult         │
│                    ├── read_slice()   ──► ReadSliceResult        │
│                    ├── write_full()   ──► WriteResult            │
│                    └── replace_range() ─► WriteResult            │
│                                                                  │
│                 ┌─────────────────────────┐                      │
│                 │      RopeCache (LRU)    │                      │
│                 │  128 MB default cap     │                      │
│                 │  key: path → Rope       │                      │
│                 │  validated by revision  │                      │
│                 └─────────────────────────┘                      │
│                              │                                   │
│                    ┌─────────┼─────────┐                         │
│                    ▼         ▼         ▼                         │
│              Path Security  Atomic   UTF-8                       │
│              (traversal     Write    Safety                      │
│               prevention)  (tmp+mv)                              │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

### Reading Files

```rust
use safe_file_ops::SafeFileOps;
use std::path::Path;

let g = SafeFileOps::with_defaults();
let root = Path::new("/path/to/repo");

// Read entire file (up to 1 MB)
let result = g.read_full(root, "src/main.rs", 1_000_000)?;

println!("Lines: {}", result.total_lines);
println!("Truncated: {}", result.is_truncated);

if let Some(reason) = &result.read_only_reason {
    println!("Read-only: {}", reason);
}

// Save revision for later write validation
let revision = result.revision;
```

### Reading Line Ranges

```rust
// Read lines 10-30 (0-indexed, exclusive end)
let slice = g.read_slice(root, "src/main.rs", 10, 20, 500_000)?;

println!("Lines {}-{} of {}", slice.start_line, slice.end_line_exclusive, slice.total_lines);
println!("More before: {}, More after: {}", slice.has_more_before, slice.has_more_after);
```

### Writing Files

```rust
// Write with optimistic locking (revision must match)
let result = g.write_full(
    root,
    "src/main.rs",
    "fn main() {}\n",
    Some(&revision),  // expected revision from previous read
    false,            // force=false, require revision match
)?;

// Force write (skip revision check)
let result = g.write_full(root, "src/new_file.rs", "// new\n", None, true)?;
```

### Replacing Line Ranges

```rust
// Replace lines 5-10 with new content
let result = g.replace_range(
    root,
    "src/main.rs",
    5,               // start_line (0-indexed)
    10,              // end_line_exclusive
    "// replaced\n",
    Some(&revision),
    false,
)?;
```

## Revision Tracking

Every read returns a `FileRevision` that captures the file's identity at that moment:

```rust
pub struct FileRevision {
    pub token: String,         // Hash of path + size + mtime
    pub len_bytes: u64,        // File size in bytes
    pub modified_unix_ns: u128, // Modification time (nanoseconds)
}
```

Writes validate the expected revision against the current file state. If another process modified the file, you get a `RevisionConflict` error with the current revision - preventing silent overwrites.

## Caching

SafeFileOps maintains an LRU cache of parsed `Rope` data structures:

- **Default capacity**: 128 MB total byte budget
- **Cache key**: Canonical file path
- **Validation**: Cache entries are invalidated when the file's revision changes
- **Eviction**: Least-recently-used entries evicted when budget exceeded
- **Write-through**: Writes update the cache with the new content

The Rope data structure (via `ropey`) enables efficient line-based operations on large files without copying the entire string.

## Path Security

All operations validate paths to prevent directory traversal:

- Relative paths only (no absolute paths, no `..` components)
- Canonicalization ensures resolved path stays within root
- Separate resolution for reads (file must exist) vs writes (parent must exist)

```rust
// These are rejected:
g.read_full(root, "../etc/passwd", max)?;       // PathTraversal
g.read_full(root, "/etc/passwd", max)?;          // InvalidRelativePath
g.read_full(root, "src/../../etc/passwd", max)?; // PathTraversal
```

## Atomic Writes

Writes use a temp-file-then-rename strategy for crash safety:

1. Write to `.{filename}.unbound.tmp.{nanos}` in the same directory
2. `fsync` the file
3. Restore original Unix permissions (if updating)
4. Atomic rename to final path
5. `fsync` the parent directory

No partial writes are ever visible to readers.

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `cache_max_bytes` | 128 MB | Maximum total bytes in the rope cache |
| `editable_max_bytes` | 4 MB | Files larger than this are marked read-only |

```rust
// Custom limits
let g = SafeFileOps::new(
    64 * 1024 * 1024,  // 64 MB cache
    2 * 1024 * 1024,   // 2 MB editable limit
);
```

## Error Types

| Error | Cause |
|-------|-------|
| `InvalidRoot` | Root path doesn't exist |
| `InvalidRelativePath` | Empty, absolute, or malformed path |
| `PathTraversal` | Path escapes the root directory |
| `NotAFile` | Target is a directory |
| `NotFound` | File doesn't exist |
| `InvalidUtf8` | File contains non-UTF-8 bytes |
| `MissingExpectedRevision` | Write without revision and `force=false` |
| `RevisionConflict` | File changed since last read |
| `InvalidRange` | Line range out of bounds |
| `Io` | Underlying filesystem error |

## Testing

```bash
cargo test -p safe-file-ops
```

16 tests covering path security, read/write operations, UTF-8 handling, cache invalidation, LRU eviction, revision conflicts, atomic writes, and Unix permission preservation.
