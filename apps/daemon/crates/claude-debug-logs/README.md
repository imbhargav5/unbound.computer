# claude-debug-logs

Structured JSONL logging for raw Claude NDJSON events emitted by the daemon.

## Purpose

This crate provides a small, file-backed logger used by `daemon-bin` to record raw
Claude output for debugging and incident analysis. It is intentionally write-only
and append-only so logs remain easy to inspect with standard tools.

## What It Records

Each recorded line is a single JSON object with:

- `timestamp` (RFC3339 UTC, microsecond precision)
- `event_code` (`daemon.claude.raw`)
- `obs_prefix` (`claude.raw`)
- `session_id`
- `sequence`
- `claude_type` (derived from raw payload `type`, normalized to lowercase)
- `raw_json` (the original raw Claude event string)

Output format is JSONL: one serialized event per line.

## File Layout

By default, files are written under:

- `~/.unbound/logs/claude-debug-logs/`

Filename format:

- `YYYY-MM-DD_<sanitized-session-id>.jsonl`

Session IDs are sanitized so only ASCII alphanumeric, `_`, and `-` remain.
All other characters are replaced with `_`.

## Environment Controls

- `UNBOUND_CLAUDE_DEBUG_LOGS_ENABLED`
  - Accepted truthy values: `1`, `true`, `yes`, `on`
  - Accepted falsy values: `0`, `false`, `no`, `off`
- `UNBOUND_CLAUDE_DEBUG_LOGS_DIR`
  - Overrides the output directory
- `UNBOUND_ENV`
  - If `UNBOUND_CLAUDE_DEBUG_LOGS_ENABLED` is unset, logging defaults to:
    - enabled for non-prod
    - disabled for `prod` / `production`

## API Surface

`ClaudeDebugLogs` is the main type:

- `ClaudeDebugLogs::from_env()` creates the logger from environment config.
- `is_enabled()` reports whether writes are active.
- `base_dir()` returns the resolved base directory.
- `record_raw_event(session_id, sequence, raw_json)` appends a JSONL line and
  returns `Ok(Some(path))` when written, `Ok(None)` when disabled.
- `extract_claude_type(raw_json)` parses and normalizes the Claude event type.

## Concurrency and Safety

Writes are guarded with an internal mutex to avoid interleaved lines across
threads. Parent directories are created on demand before append.

## Typical Integration

The daemon can instantiate one logger once at startup via `from_env()` and call
`record_raw_event(...)` from Claude stream handling code paths when debugging is
required.
