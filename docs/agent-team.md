# Agent Teams (Claude Code Stream JSON)

This document describes the **agent team** schema surfaced in Claude Code's `--output-format stream-json` output, with examples based on `/Users/bhargavponnapalli/Desktop/agent-swarm-example.json`.

## Purpose And Scope

Agent teams allow Claude Code to spawn multiple parallel sub‑agents and coordinate them. The stream emits **tool invocations** and **tool results** that describe:

- Team creation and metadata
- Individual teammate spawns
- Inter‑agent messaging and broadcasts
- Shutdown requests and cleanup
- Session‑level completion metrics

This doc focuses on **stream JSON shapes**, **lifecycle events**, and **UI routing guidance** for parallel cards.

## Core Entities

These fields appear in stream JSON and are the primary identifiers to use for grouping and routing:

- `team_name`: String identifier for the team (e.g. `"codebase-gap-analysis"`).
- `teammate_id`: Stable agent identifier in the team (e.g. `"swift-expert@codebase-gap-analysis"`).
- `agent_id` / `agentId`: Agent identifier (note both spellings appear). Normalize these.
- `lead_agent_id`: The team lead (present in team config summary).
- `team_file_path`: Path to the team config on disk.

## Lifecycle

Typical team lifecycle in the stream:

1. **Spawn team** via `Teammate` tool (`operation: "spawnTeam"`).
2. **Spawn teammates** (reported by tool_use_result with `status: "teammate_spawned"`).
3. **Run work** (agents operate in background, messages flow).
4. **Shutdown request** (via `SendMessage` tool with `type: "shutdown_request"`).
5. **Cleanup** (via `Teammate` tool with `operation: "cleanup"`).

## Messaging

`SendMessage` is the canonical tool for inter‑agent communication. It supports:

- `type: "message"` (direct message)
- `type: "broadcast"` (team‑wide)
- `type: "shutdown_request"` (graceful termination)

Tool results echo **routing metadata** which you can use to drive UI.

## Completion Signals

There are two completion signals to watch:

- **Per‑agent**: A `SendMessage` with `type: "shutdown_request"` returns a `request_id` and `target`.
- **Team**: `Teammate` cleanup tool_use_result with `success: true` and `team_name`.
- **Session**: A top‑level `type: "result"` event provides summary usage/cost/duration data.

## Normalization Rules

The stream contains both `agentId` and `agent_id`. Normalize as:

1. If `teammate_id` exists, use it.
2. Else if `agent_id` exists, use it.
3. Else if `agentId` exists, use it.
4. Else fall back to `name`.

## Examples (NDJSON)

All examples are **valid NDJSON** lines and match the field shapes seen in `/Users/bhargavponnapalli/Desktop/agent-swarm-example.json`.

### 1) Spawn Team (`Teammate` tool_use)

```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01VUtvvpgg4cERjbEoL9zEhE","name":"Teammate","input":{"operation":"spawnTeam","team_name":"codebase-gap-analysis","description":"Analyze Swift/Rust codebase for implementation gaps and missing features","agent_type":"architect"}}]}}}
```

### 2) Team Created (tool_use_result summary)

```json
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01VUtvvpgg4cERjbEoL9zEhE","type":"tool_result","content":[{"type":"text","text":"Team created."}]}]},"tool_use_result":{"team_name":"codebase-gap-analysis","team_file_path":"/Users/bhargavponnapalli/.claude/teams/codebase-gap-analysis/config.json","lead_agent_id":"team-lead@codebase-gap-analysis"}}
```

### 3) Spawn Teammate (`Task` tool_use)

```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01KGwLUDGUZJeLUnywt5XyVa","name":"Task","input":{"description":"SwiftUI expert gap analysis","prompt":"You are a **Senior SwiftUI Expert** ...","subagent_type":"general-purpose","team_name":"codebase-gap-analysis","name":"swift-expert","run_in_background":true,"max_turns":60}}]}}}
```

### 4) Teammate Spawned (tool_use_result)

```json
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01KGwLUDGUZJeLUnywt5XyVa","type":"tool_result","content":[{"type":"text","text":"Spawned successfully."}]}]},"tool_use_result":{"status":"teammate_spawned","teammate_id":"swift-expert@codebase-gap-analysis","agent_id":"swift-expert@codebase-gap-analysis","agent_type":"general-purpose","model":"claude-opus-4-6","name":"swift-expert","color":"blue","tmux_session_name":"in-process","tmux_window_name":"in-process","tmux_pane_id":"in-process","team_name":"codebase-gap-analysis","is_splitpane":false,"plan_mode_required":false}}
```

### 5) SendMessage: Direct Message

**Tool use**
```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_015WnhkZuKSdU3qU1LTgLXDL","name":"SendMessage","input":{"type":"message","recipient":"swift-expert","content":"Please wrap up your analysis...","summary":"Requesting Swift analysis report"}}]}}}
```

**Tool result**
```json
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_015WnhkZuKSdU3qU1LTgLXDL","type":"tool_result","content":"Message sent."}]},"tool_use_result":{"success":true,"message":"Message sent to swift-expert's inbox","routing":{"sender":"team-lead","target":"@swift-expert","targetColor":"blue","summary":"Requesting Swift analysis report","content":"Please wrap up your analysis..."}}}
```

### 6) SendMessage: Broadcast

**Tool use**
```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_015Vi9RtZcv6zx1VRevjAopD","name":"SendMessage","input":{"type":"broadcast","content":"URGENT: Please immediately send me whatever findings you have so far...","summary":"URGENT: Write findings to file now"}}]}}}
```

**Tool result**
```json
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_015Vi9RtZcv6zx1VRevjAopD","type":"tool_result","content":"Broadcast sent."}]},"tool_use_result":{"success":true,"message":"Message broadcast to 2 teammate(s): swift-expert, rust-expert","recipients":["swift-expert","rust-expert"],"routing":{"sender":"team-lead","target":"@team","summary":"URGENT: Write findings to file now","content":"URGENT: Please immediately send me whatever findings you have so far..."}}}
```

### 7) SendMessage: Shutdown Request

**Tool use**
```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_015SXmpNrHRLVRBJFKhCiiYM","name":"SendMessage","input":{"type":"shutdown_request","recipient":"swift-expert","content":"Analysis complete, thank you for the thorough report. Shutting down."}}]}}}
```

**Tool result**
```json
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_015SXmpNrHRLVRBJFKhCiiYM","type":"tool_result","content":"Shutdown request sent."}]},"tool_use_result":{"success":true,"message":"Shutdown request sent to swift-expert. Request ID: shutdown-1770325847779@swift-expert","request_id":"shutdown-1770325847779@swift-expert","target":"swift-expert"}}
```

### 8) Teammate Cleanup (Failure + Success)

**Failure**
```json
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01TNzA2Stp38wHgy3LGbeWzU","type":"tool_result","content":"Cleanup failed."}]},"tool_use_result":{"success":false,"message":"Cannot cleanup team with 2 active member(s): swift-expert, rust-expert. Use requestShutdown to gracefully terminate teammates first.","team_name":"codebase-gap-analysis"}}
```

**Success**
```json
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01GpXR7TktP2J5vxdP7Ym5ck","type":"tool_result","content":"Cleanup complete."}]},"tool_use_result":{"success":true,"message":"Cleaned up directories and worktrees for team \"codebase-gap-analysis\"","team_name":"codebase-gap-analysis"}}
```

### 9) Session Summary (`type: "result"`)

```json
{"type":"result","subtype":"success","is_error":false,"duration_ms":10786,"duration_api_ms":1204342,"num_turns":2,"total_cost_usd":8.559937750000001,"result":"Team cleaned up. The complete analysis is in the report above...","usage":{"input_tokens":4,"cache_creation_input_tokens":14102,"cache_read_input_tokens":145459,"output_tokens":216,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":14102,"ephemeral_5m_input_tokens":0}},"modelUsage":{"claude-opus-4-6":{"inputTokens":793,"outputTokens":55704,"cacheReadInputTokens":6938095,"cacheCreationInputTokens":565418,"webSearchRequests":0,"costUSD":8.399475,"contextWindow":200000,"maxOutputTokens":32000},"claude-haiku-4-5-20251001":{"inputTokens":25147,"outputTokens":5651,"cacheReadInputTokens":412770,"cacheCreationInputTokens":52627,"webSearchRequests":0,"costUSD":0.16046275,"contextWindow":200000,"maxOutputTokens":64000}}}
```

## UI Routing Guide

Use the following mapping to drive a parallel cards UI:

- **Team grouping**: group cards by `team_name`.
- **Card identity**: use `teammate_id` when present; else `agent_id` / `agentId`.
- **Spawn events**: when `status: "teammate_spawned"` arrives, create a new card with `color`, `model`, and `agent_type` badges.
- **Message routing**: route `SendMessage` tool results by `routing.target`:
  - `@swift-expert` → the agent card
  - `@team` → team‑level timeline banner
- **Shutdown state**: set card to `shutting down` when a `shutdown_request` ack arrives.
- **Cleanup state**: set team header to `cleaned_up` on cleanup success; show error on cleanup failure.
- **Session summary**: render the `type: "result"` event as a session summary card (usage/cost/duration).

## Test Scenarios

1. Teammate spawn yields a new card with correct `color` and `model`.
2. Broadcast message shows team‑level notification with `recipients`.
3. `shutdown_request` ack flips agent card to “shutting down.”
4. Cleanup failure leaves team active and displays error message.
5. `type: "result"` renders session summary metrics.
