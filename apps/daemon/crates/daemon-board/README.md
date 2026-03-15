# daemon-board

Local board domain service for companies, agents, projects, issues, approvals,
and issue workspace bootstrapping.

## Purpose

`daemon-board` encapsulates board/business logic used by daemon IPC handlers.
It runs on top of `daemon-database` and `agent-session-sqlite-persist-core`
without owning transport concerns.

## Domain Model

The crate exposes serializable model types for:

- `Company`
- `Agent`
- `Goal`
- `Project` and `ProjectWorkspace`
- `Issue` and `IssueComment`
- `Approval`
- `Workspace`

It also defines input payload types for creation/update flows such as
`CreateCompanyInput`, `CreateAgentInput`, `CreateProjectInput`,
`CreateIssueInput`, `AddIssueCommentInput`, and `ApprovalDecisionInput`.

## Core Service APIs

`service.rs` provides async operations grouped by domain:

- Company: list, get, create
- Agent: list, get, create
- Goal: list
- Project: list, get, create
- Issue: list, get, create, comment list/add, checkout
- Approval: list, get, approve
- Workspace: list, get

Notable behavior:

- `create_company` seeds a default local board user, creates a CEO agent,
  grants default owner permissions, and records activity events.
- Agent creation can require approval depending on company policy.
- Company creation scaffolds agent home directories under the daemon path layout
  and rolls back DB state if scaffolding fails.
- `start_issue_workspace` bridges board issue execution to the session writer
  interface from `agent-session-sqlite-persist-core`.

## Storage and Integration

The crate uses:

- `AsyncDatabase::call_with_operation(...)` for serialized DB execution
- `daemon_config_and_utils::Paths` for company/agent filesystem layout
- `daemon_database::queries` for repository/session persistence helpers
- `SessionWriter` trait integration for issue checkout workspace startup

## Error Model

`BoardError` wraps:

- `DatabaseError`
- `std::io::Error`
- `serde_json::Error`
- domain errors (`NotFound`, `Conflict`, `InvalidInput`, `Runtime`)

Public result alias:

- `type BoardResult<T> = Result<T, BoardError>`

## Typical Usage

`daemon-bin` board IPC handlers parse request params into board input structs,
call `daemon_board::service::*`, and map `BoardError` to IPC error responses.
