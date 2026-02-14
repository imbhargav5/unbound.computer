# Device Capabilities Schema

This document defines the canonical JSON structure stored in `devices.capabilities` (Supabase) and consumed by the daemon, macOS, and iOS clients.

## Goals
- Max 2 levels of nesting.
- Stable keys + types across all platforms.
- Forward-compatible via versioning and permissive readers.

## Top-Level Shape
```json
{
  "cli": {
    "claude": {"installed": true, "path": "/usr/local/bin/claude", "models": ["claude-opus-4-5-20251101"]},
    "gh": {"installed": true, "path": "/usr/local/bin/gh"},
    "codex": {"installed": false, "path": null},
    "ollama": {"installed": true, "path": "/opt/homebrew/bin/ollama"}
  },
  "metadata": {
    "schema_version": 1,
    "collected_at": "2026-02-14T08:00:00Z"
  }
}
```

## Rules
- Only two levels of object nesting are allowed.
  - Level 1: top-level keys (e.g., `cli`, `metadata`).
  - Level 2: category entries (e.g., `cli.claude`, `cli.gh`, `metadata`).
  - Values inside level-2 objects must be primitives, nulls, or arrays (no nested objects).
- Readers must ignore unknown keys for forward compatibility.
- Writers must include `metadata.schema_version` and `metadata.collected_at`.

## Field Definitions

### `cli` (object)
Contains tool availability and paths for CLI-based dependencies.

Each key under `cli` is a tool name (currently `claude`, `gh`, `codex`, `ollama`).

Tool object fields:
- `installed` (boolean, required): Whether the tool is present.
- `path` (string | null, required): Resolved binary path if installed, otherwise `null`.
- `models` (string[], optional): Only for tools that expose model lists (currently `claude`).

### `metadata` (object)
- `schema_version` (number, required): Increment on backward-incompatible changes.
- `collected_at` (string, required): ISO-8601 UTC timestamp when capabilities were collected.

## Examples

### Full
```json
{
  "cli": {
    "claude": {"installed": true, "path": "/usr/local/bin/claude", "models": ["claude-opus-4-5-20251101"]},
    "gh": {"installed": true, "path": "/usr/local/bin/gh"},
    "codex": {"installed": false, "path": null},
    "ollama": {"installed": true, "path": "/opt/homebrew/bin/ollama"}
  },
  "metadata": {
    "schema_version": 1,
    "collected_at": "2026-02-14T08:00:00Z"
  }
}
```

### Partial (missing tools)
```json
{
  "cli": {
    "claude": {"installed": false, "path": null},
    "gh": {"installed": true, "path": "/usr/local/bin/gh"}
  },
  "metadata": {
    "schema_version": 1,
    "collected_at": "2026-02-14T08:00:00Z"
  }
}
```

### Missing `models`
```json
{
  "cli": {
    "claude": {"installed": true, "path": "/usr/local/bin/claude"}
  },
  "metadata": {
    "schema_version": 1,
    "collected_at": "2026-02-14T08:00:00Z"
  }
}
```
