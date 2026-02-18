# iOS Session Detail Parser Contract

This document defines the parser/mapper/realtime contract for Session Detail rendering in iOS.

## Goal

Produce a deterministic, UI-ready timeline from encrypted session payloads with consistent behavior across:

- initial decrypted load (`SessionDetailMessageService.loadMessages`)
- realtime updates (`SessionDetailMessageService.messageUpdates`)
- fixture previews (`SessionDetailFixtureMessageLoader`)

## In Scope

- `SessionMessagePayloadParser` role/type/raw_json parsing.
- `SessionDetailMessageMapper` ordering, dedupe, and sub-agent grouping.
- `SessionDetailMessageService` initial/realtime convergence and row identity handling.
- `SessionContentBlock`-driven rendering contracts in:
  - `MessageBubbleView`
  - `SessionContentBlockView`
  - `ParallelAgentsView`
  - `StandaloneToolCallsView`
  - `ToolCallView`

## Shared Claude Fixtures

Shared Claude parser fixtures live at:

`apps/shared/ClaudeConversationTimeline/Fixtures/claude-parser-contract-fixtures.json`

iOS and macOS tests load this file to keep timeline parsing consistent across platforms.

## Out of Scope

- Daemon protocol/schema changes.
- Remote-command feature expansion unrelated to timeline rendering.
- Global chat redesign unrelated to parser-state fidelity.

## Contract

1. Unknown or malformed payloads must resolve deterministically (fallback text/system behavior, never random ordering).
2. `raw_json` wrappers are recursively unwrapped up to parser limits; wrapped success/error results follow the same visibility rules as unwrapped payloads.
3. Successful `result` payloads are hidden; error results render as visible error blocks.
4. Protocol artifact rows (for example tool_result envelopes) do not create visible user chat rows unless real user-authored text is present.
5. Sub-agent/task grouping converges even when child tools arrive before parent Task messages.
6. Tool and sub-agent statuses are parsed when present; missing status defaults to `.completed`.
7. Tool input/output details are preserved when present for expandable tool detail rows.
8. Duplicate tool updates keep latest state for the same tool identity.
9. Duplicate message IDs keep latest row state (latest-write-wins) for both initial-load and realtime pipelines.
10. Sequence ties are resolved deterministically with created-at and row-id tie breakers.
11. Consecutive parsed `.subAgentActivity` blocks are batched into one grouped render block in `MessageBubbleView`.

## Behavior Matrix

| Scenario | Expected Behavior | Tests |
| --- | --- | --- |
| assistant text + tool_use parsing | assistant text is visible; standalone tool blocks render with summaries | `SessionMessagePayloadParserTests.testTimelineEntryParsesAssistantToolUseBlocks` |
| tool status/input/output parsing | tool status maps to running/completed/failed; input/output are preserved | `SessionMessagePayloadParserTests.testTimelineEntryParsesToolUseStatusInputAndOutput`, `ClaudeTimelineMessageMapperTests.testMapEntriesMapsToolStatusInputAndOutput` |
| task status/result parsing | Task blocks map to sub-agent status/result and carry child tool status | `SessionMessagePayloadParserTests.testTimelineEntryParsesTaskStatusAndResult`, `ClaudeTimelineMessageMapperTests.testMapEntriesMapsSubAgentStatusResultAndChildToolStatus` |
| child tool before Task parent | final timeline converges into grouped sub-agent activity | `SessionDetailMessageServiceTests.testMessageUpdatesConvergesWhenChildToolArrivesBeforeParentTask` |
| duplicate tool update keeps latest state | same tool identity is replaced by latest summary/state | `SessionDetailMessageMapperTests.testMapRowsMergesDuplicateSubAgentActivitiesAndDeduplicatesToolsById`, `SessionDetailMessageServiceTests.testLoadMessagesDeduplicatesChildToolUpdatesByToolUseId` |
| repeated task updates preserve terminal status | stale running task updates do not regress finished task state | `SessionDetailMessageMapperTests.testMapRowsKeepsStableSubAgentStatusAndResultAcrossRepeatedTaskUpdates` |
| result success hidden, result error shown | successful results are omitted; error results are visible system errors | `SessionMessagePayloadParserTests.testTimelineEntryHidesSuccessfulResult`, `SessionMessagePayloadParserTests.testTimelineEntryShowsErrorResult` |
| protocol artifacts hidden, real user text preserved | tool_result-only envelopes hidden; user-authored text remains | `SessionMessagePayloadParserTests.testTimelineEntryHidesUserToolResultEnvelope`, `SessionMessagePayloadParserTests.testTimelineEntryKeepsRealUserTextWhenToolResultContainsProtocolArtifact` |
| wrapped raw_json success/failure handling | wrapped payloads parse consistently; malformed wrappers fail deterministically | `SessionMessagePayloadParserTests.testTimelineEntryUnwrapsNestedRawJsonAssistantPayload`, `SessionMessagePayloadParserTests.testTimelineEntryHidesInvalidRawJsonWrapperPayload` |
| malformed/unknown payload deterministic fallback | fallback role/content behavior is stable for unknown/malformed payloads | `SessionMessagePayloadParserTests.testTimelineEntryTreatsPlaintextAsUserMessage`, `SessionMessagePayloadParserTests.testRoleReturnsSystemForUnknownType` |
| realtime + initial load order/dedupe consistency | equivalent rows converge to equivalent timeline output | `SessionDetailMessageServiceTests.testInitialLoadAndRealtimeConvergeToSameTimelineForEquivalentRows`, `SessionDetailMessageServiceTests.testLoadMessagesDeduplicatesInitialRowsByMessageIdWithLatestWriteWins`, `SessionDetailMessageServiceTests.testMessageUpdatesDeduplicatesRealtimeRowsByMessageID` |
| message display batching parity | consecutive sub-agent activities render as one grouped block while standalone tools stay grouped separately | `SessionParsedDisplayPlannerTests.testDisplayBlocksGroupsConsecutiveSubAgentActivitiesIntoSingleParallelGroup`, `SessionParsedDisplayPlannerTests.testDisplayBlocksPreservesStandaloneToolGroupingAlongsideParallelSubAgentGrouping` |

## Fixture Workflow

Refresh fixture:

```bash
cd apps/ios
./scripts/export_max_session_fixture.sh
```

Validate fixture decode + mapping:

```bash
xcodebuild -project apps/ios/unbound-ios.xcodeproj -scheme unbound-ios -destination "platform=iOS Simulator,name=iPhone 17,OS=26.2" -only-testing:unbound-iosTests/SessionDetailFixtureMessageLoaderTests test
```

Validate parser + mapper + realtime matrix:

```bash
xcodebuild -project apps/ios/unbound-ios.xcodeproj -scheme unbound-ios -destination "platform=iOS Simulator,name=iPhone 17,OS=26.2" -only-testing:unbound-iosTests/SessionMessagePayloadParserTests -only-testing:unbound-iosTests/SessionDetailMessageMapperTests -only-testing:unbound-iosTests/SessionDetailMessageServiceTests test
```

## Component Preview Matrix

Use these previews for state/design iteration independent of JSON payload shape:

- `ParallelAgentsView.swift` previews: collapsed/all-expanded/partial-running grouped states with compact and expanded tool rows.
- `SubAgentView.swift` previews: fallback wrapper compatibility around grouped parallel rendering.
- `StandaloneToolCallsView.swift` previews: single/multi tool lists, collapsed/expanded behavior.
- `ToolCallView.swift` previews: standalone tool card states and long summary handling.
- `MessageBubbleView.swift` preview `Parsed Tool/SubAgent States`: mixed assistant text/tool/sub-agent/error cases with duplicate updates.
- `SessionContentBlockView.swift` preview `Session Content Blocks`: text/tool/sub-agent/error block rendering contract.
