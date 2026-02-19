# macOS Claude Parser Contract

## Goal

Define one canonical parse contract for both historical message loading and live streaming state so ChatPanel and SessionDetail render the same semantic states.

## Scope

In scope:
- `ClaudeMessageParser` behavior for assistant/user/result/system payloads.
- `SessionLiveState` handling for active tools, sub-agents, tool results, and terminal result transitions.
- `ChatMessageGrouper` behavior for child-tool attachment and dedupe.
- Typed UI rendering through `ParallelAgentsView`, `StandaloneToolCallsView`, and tool row components.

Out of scope:
- Daemon protocol/schema changes.
- Transport/auth/session persistence redesign.
- New chat features unrelated to parser/rendering consistency.

## Shared Claude Fixtures

Shared Claude parser fixtures live at:

`apps/shared/ClaudeConversationTimeline/Fixtures/claude-parser-contract-fixtures.json`

macOS and iOS tests load this file to keep timeline parsing consistent across platforms.

## Canonical Behavior Matrix

| Input Event | Parser / Live Interpretation | UI Expectation |
| --- | --- | --- |
| `assistant` with text | Emits `.text` content | Text row visible |
| `assistant` with `tool_use` | Emits `.toolUse` or `.subAgentActivity` (`Task`) | Tool/sub-agent cards render from typed models |
| same-id `assistant` text then same-id `assistant` `tool_use` | Merged by `message.id`; text retained while tools update | Commentary remains visible and tool/sub-agent cards appear in same row |
| duplicate same-id `assistant` text update | Latest non-empty text wins for that `message.id` | No duplicate rows; most recent commentary text visible |
| child tool before `Task` parent | Queued then attached when parent appears | No orphan child card when parent arrives |
| duplicate `tool_use_id` update | Latest update wins | No duplicate cards, no stale status |
| same-id tool/sub-agent shown in message and live/history surfaces | Message-surface tool IDs are canonical for rendering | Bottom live/history duplicates are suppressed |
| inline tool/sub-agent status rendering | Uses parser/live model status directly | Running stays running until completion event (no view-layer auto-complete) |
| consecutive `subAgentActivity` blocks | Batched into a single parallel group render block | One grouped Parallel Agents card |
| `user` with `tool_result` success | Matched tool becomes `.completed` | Running indicator clears |
| `user` with `tool_result` error | Matched tool becomes `.failed` | Failed state shown |
| `user` with `tool_result` where `content` is text array | Text fragments are extracted and joined with newlines | Tool/sub-agent result text is visible (not dropped) |
| parent `Task` `tool_result` | Matched sub-agent parent updates `.status`/`.result` | Parent card switches running → terminal state correctly |
| parent `Task` result text rendering | Stored on sub-agent `.result` only | Output appears in expanded sub-agent card without duplicate standalone text row |
| `assistant` `tool_use` with `name=TodoWrite` | Mapped to typed `TodoList` content | Todo checklist card renders in message surface (no duplicate generic tool card) |
| `result` success | Hidden as message; running tools finalize to completed in live state | No stale running after turn ends |
| `result` error | Error surfaced (historical parse) and running tools finalize to failed (live state) | Failure is visible and deterministic |
| wrapped `raw_json` payload | Unwrapped up to bounded depth | Same semantics as unwrapped payload |
| protocol artifact-only row | Filtered | No raw protocol JSON shown to user |
| malformed/unknown payload | Deterministic system fallback text | No crashes; fallback row is stable |

## Historical and Live Parity Rules

- Parse semantics must match whether data arrives from `loadMessages()` or `handleClaudeEvent(...)`.
- Grouping and dedupe behavior must be identical for:
  - standalone tool calls
  - sub-agent child tools
  - child-before-parent ordering
- End-of-turn behavior (`type=result`) must leave no active `running` tools in archived history.

## Typed Output to Component Mapping

| Typed state | Rendering entry point |
| --- | --- |
| `MessageContent.todoList` | `TodoListView` |
| `MessageContent.subAgentActivity` | `ParallelAgentsView(activities:)` (grouped render block) |
| active `ActiveSubAgent` | `ParallelAgentsView(activeSubAgents:)` |
| grouped standalone `ToolUse` | `StandaloneToolCallsView(historyTools:)` |
| active standalone `ActiveTool` | `StandaloneToolCallsView(activeTools:)` |
| tool row details | `ParallelAgentToolRowView` / `ToolUseView` / `ToolViewRouter` |
| parser errors | `ErrorContentView` |

## Fixture Workflow

Base fixture file:
- `apps/macos/unbound-macos/Resources/PreviewFixtures/session-detail-max-messages.json`

Regenerate from local SQLite (run at repo root):

```bash
./apps/ios/scripts/export_max_session_fixture.sh \
  "$HOME/Library/Application Support/com.unbound.macos/unbound.sqlite" \
  "apps/macos/unbound-macos/Resources/PreviewFixtures/session-detail-max-messages.json"
```

## Preview Workflow (Design Iteration)

Primary preview surfaces:
- `ParallelAgentsView` preview matrix (completed/running/failed, collapsed/expanded states)
- `StandaloneToolCallsView` preview matrix (single/multi, running/completed/failed, expanded/collapsed)
- `ToolUseView` preview matrix (expanded/collapsed, success/failure)
- `SessionDetailView` scenario previews (fixture + synthetic variants)

When adjusting visuals, update preview data first, then validate against fixture scenarios.

## Verification Checklist

1. Build app target:

```bash
xcodebuild -project apps/macos/unbound-macos.xcodeproj -scheme unbound-macos -configuration Debug -destination "platform=macOS" build
```

2. Run parser/grouping/live tests (test target currently includes known unrelated database test compile failures; parser files should still compile):

```bash
xcodebuild -project apps/macos/unbound-macos.xcodeproj -scheme unbound-macos -destination "platform=macOS" \
  -only-testing:unbound-macosTests/ClaudeMessageParserContractTests \
  -only-testing:unbound-macosTests/SessionLiveStateStreamingTests \
  -only-testing:unbound-macosTests/ChatMessageGroupingTests \
  test
```

3. Spot-check Canvas previews for the component matrices above.
