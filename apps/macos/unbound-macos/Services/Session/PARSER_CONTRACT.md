# macOS Claude Parser Contract

## Goal

Define one canonical parse contract for both historical message loading and live streaming state so ChatPanel and SessionDetail render the same semantic states.

## Scope

In scope:
- `ClaudeMessageParser` behavior for assistant/user/result/system payloads.
- `SessionLiveState` handling for active tools, sub-agents, tool results, and terminal result transitions.
- `ChatMessageGrouper` behavior for child-tool attachment and dedupe.
- Typed UI rendering through `SubAgentView`, `StandaloneToolCallsView`, and tool row components.

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
| child tool before `Task` parent | Queued then attached when parent appears | No orphan child card when parent arrives |
| duplicate `tool_use_id` update | Latest update wins | No duplicate cards, no stale status |
| `user` with `tool_result` success | Matched tool becomes `.completed` | Running indicator clears |
| `user` with `tool_result` error | Matched tool becomes `.failed` | Failed state shown |
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
| `MessageContent.subAgentActivity` | `SubAgentView(activity:)` |
| active `ActiveSubAgent` | `SubAgentView(activeSubAgent:)` |
| grouped standalone `ToolUse` | `StandaloneToolCallsView(historyTools:)` |
| active standalone `ActiveTool` | `StandaloneToolCallsView(activeTools:)` |
| tool row details | `ToolUseView` / `ToolViewRouter` |
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
- `SubAgentView` preview matrix (active/historical, completed/failed, expanded/collapsed)
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
