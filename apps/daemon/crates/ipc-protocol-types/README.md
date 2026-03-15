# ipc-protocol-types

Pure IPC protocol data model for the Unbound daemon (types + serialization only).

## Purpose

This crate defines the shared wire contract between daemon clients and server.
It intentionally contains no socket I/O and no async runtime code.

## Core Types

- `Method` (IPC method enum, serde wire names)
- `Request` (`id`, `method`, optional `params`, optional trace `context`)
- `Response` (`result` or `error`)
- `Event` (server-pushed subscription event)
- `EventType`
- `TraceContext` (`traceparent`, optional `tracestate`)

## Method Surface (65 total)

Method groups:

- Health/lifecycle (`health`, `shutdown`)
- Sessions (`session.list/create/get/update/delete`)
- Board domains
  - Companies (`company.list/create/get`)
  - Agents (`agent.list/create/get`)
  - Goals (`goal.list`)
  - Projects (`project.list/create/get`)
  - Issues (`issue.list/create/get`, comments, checkout)
  - Approvals (`approval.list/get/approve`)
  - Workspaces (`workspace.list/get`)
- Messages (`message.list/send`)
- Outbox (`outbox.status`)
- Repositories
  - lifecycle (`repository.list/add/remove`)
  - settings (`repository.get_settings/update_settings`)
  - file ops (`list_files/read_file/read_file_slice/write_file/replace_file_range`)
- Claude process control (`claude.send/status/stop`)
- Streaming (`session.subscribe/unsubscribe`)
- Git (`git.status/diff_file/log/branches/stage/unstage/discard/commit/push`)
- GitHub CLI (`gh.auth_status/pr_create/pr_view/pr_list/pr_checks/pr_merge`)
- System (`system.check_dependencies`)
- Terminal (`terminal.run/status/stop`)

## Event Types

Current event variants:

- `message`
- `streaming_chunk`
- `status_change`
- `initial_state`
- `ping`
- `terminal_output`
- `terminal_finished`
- `claude_event`
- `session_created`
- `session_deleted`

## Response Optimizations

`Response::success_raw(id, raw_json)` allows embedding an already-serialized
`result` payload without re-serializing large response objects.

## Error Codes

Exports standard JSON-RPC style constants plus daemon-specific extensions:

- `PARSE_ERROR`
- `INVALID_REQUEST`
- `METHOD_NOT_FOUND`
- `INVALID_PARAMS`
- `INTERNAL_ERROR`
- `NOT_AUTHENTICATED`
- `NOT_FOUND`
- `CONFLICT`

## Design Guarantees

- Stable wire names via explicit serde renames
- UUID request IDs by default helper constructors
- Trace context fields are optional and omitted when absent
- Data-only crate suitable for reuse across daemon/client binaries
