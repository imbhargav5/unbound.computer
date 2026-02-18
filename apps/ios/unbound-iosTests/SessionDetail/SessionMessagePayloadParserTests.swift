import XCTest

@testable import unbound_ios

final class SessionMessagePayloadParserTests: XCTestCase {
    func testRoleUsesEncryptedPayloadRoleField() {
        let role = SessionMessagePayloadParser.role(from: #"{"role":"assistant","content":"hello"}"#)
        XCTAssertEqual(role, .assistant)
    }

    func testRoleFallsBackToTypeWhenRoleMissing() {
        let role = SessionMessagePayloadParser.role(from: #"{"type":"user_prompt_command","content":"hello"}"#)
        XCTAssertEqual(role, .user)
    }

    func testDisplayTextReadsContentFragments() {
        let text = SessionMessagePayloadParser.displayText(
            from: #"{"content":[{"text":"line 1"},{"content":"line 2"}]}"#
        )
        XCTAssertEqual(text, "line 1\nline 2")
    }

    func testDisplayTextReturnsPlaintextForNonJson() {
        let text = SessionMessagePayloadParser.displayText(from: "plain text payload")
        XCTAssertEqual(text, "plain text payload")
    }

    func testTimelineEntryTreatsPlaintextAsUserMessage() {
        let entry = SessionMessagePayloadParser.timelineEntry(from: "plain text payload")

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .user)
        XCTAssertEqual(entry?.content, "plain text payload")
        XCTAssertEqual(entry?.blocks.count, 1)
    }

    func testTimelineEntryParsesAssistantToolUseBlocks() {
        let payload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Looking now"},{"type":"tool_use","id":"tool_1","name":"Read","input":{"file_path":"/repo/README.md"}}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .assistant)
        XCTAssertEqual(entry?.blocks.count, 2)

        guard let blocks = entry?.blocks else {
            XCTFail("Expected parsed blocks")
            return
        }

        guard case .text(let textBlock) = blocks[0] else {
            XCTFail("Expected first block to be text")
            return
        }
        XCTAssertEqual(textBlock, "Looking now")

        guard case .toolUse(let toolBlock) = blocks[1] else {
            XCTFail("Expected second block to be tool use")
            return
        }
        XCTAssertEqual(
            toolBlock.toolName,
            "Read",
            "toolUseId=\(toolBlock.toolUseId ?? "nil"), summary=\(toolBlock.summary)"
        )
        XCTAssertEqual(toolBlock.summary, "Read /repo/README.md")
    }

    func testTimelineEntryGroupsSubAgentToolsWithinAssistantPayload() {
        let payload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"Explore","description":"Search codebase"}},{"type":"tool_use","id":"tool_1","name":"Read","parent_tool_use_id":"task_1","input":{"file_path":"/repo/README.md"}},{"type":"tool_use","id":"tool_2","name":"Grep","parent_tool_use_id":"task_1","input":{"pattern":"TODO"}}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .assistant)
        XCTAssertEqual(entry?.blocks.count, 1)

        guard let firstBlock = entry?.blocks.first else {
            XCTFail("Expected a grouped sub-agent block")
            return
        }

        guard case .subAgentActivity(let activity) = firstBlock else {
            XCTFail("Expected sub-agent activity block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_1")
        XCTAssertEqual(activity.subagentType, "Explore")
        XCTAssertEqual(activity.tools.count, 2)
        XCTAssertEqual(activity.tools.map(\.toolName), ["Read", "Grep"])
    }

    func testTimelineEntryHidesUserToolResultEnvelope() {
        let payload = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool_1","is_error":false}]}}"#
        XCTAssertNil(SessionMessagePayloadParser.timelineEntry(from: payload))
    }

    func testTimelineEntryShowsUserTextMessage() {
        let payload = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Please run tests"}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .user)
        XCTAssertEqual(entry?.content, "Please run tests")
        XCTAssertEqual(entry?.blocks.count, 1)
    }

    func testTimelineEntryHidesUserToolUseEnvelope() {
        let payload = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_use","id":"tool_1","name":"Read","input":{"file_path":"README.md"}}]}}"#

        XCTAssertNil(SessionMessagePayloadParser.timelineEntry(from: payload))
    }

    func testTimelineEntryShowsUserPromptCommandAsUser() {
        let payload = #"{"type":"user_prompt_command","message":"Ship this fix"}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .user)
        XCTAssertEqual(entry?.content, "Ship this fix")
    }

    func testTimelineEntryHidesSuccessfulResult() {
        let payload = #"{"type":"result","is_error":false,"result":"done"}"#
        XCTAssertNil(SessionMessagePayloadParser.timelineEntry(from: payload))
    }

    func testTimelineEntryShowsErrorResult() {
        let payload = #"{"type":"result","is_error":true,"result":"failed command"}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .system)
        XCTAssertEqual(entry?.content, "failed command")

        guard let blocks = entry?.blocks else {
            XCTFail("Expected blocks")
            return
        }
        guard blocks.count == 1 else {
            XCTFail("Expected exactly one block, got \(blocks.count)")
            return
        }

        guard case .error(let message) = blocks[0] else {
            XCTFail("Expected error block")
            return
        }
        XCTAssertEqual(message, "failed command")
    }

    func testTimelineEntryUnwrapsRawJsonAssistantPayload() {
        let wrapped = #"{"raw_json":"{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"wrapped text\"}]}}"}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: wrapped)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .assistant)
        XCTAssertEqual(entry?.content, "wrapped text")
        XCTAssertEqual(entry?.blocks.count, 1)
    }

    func testTimelineEntryHidesInvalidRawJsonWrapperPayload() {
        let wrapped = #"{"raw_json":"{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"broken\"}]"}"#

        XCTAssertNil(SessionMessagePayloadParser.timelineEntry(from: wrapped))
    }

    func testTimelineEntryUnwrapsNestedRawJsonAssistantPayload() {
        let nested = #"{"raw_json":"{\"raw_json\":\"{\\\"type\\\":\\\"assistant\\\",\\\"message\\\":{\\\"role\\\":\\\"assistant\\\",\\\"content\\\":[{\\\"type\\\":\\\"text\\\",\\\"text\\\":\\\"double wrapped\\\"}]}}\"}"}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: nested)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .assistant)
        XCTAssertEqual(entry?.content, "double wrapped")
    }

    func testRoleUsesResolvedRawJsonTypeWhenWrapped() {
        let wrapped = #"{"raw_json":"{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"wrapped role\"}]}}"}"#
        XCTAssertEqual(SessionMessagePayloadParser.role(from: wrapped), .assistant)
    }

    func testTimelineEntryKeepsRealUserTextWhenToolResultContainsProtocolArtifact() {
        let payload = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool_1","content":"{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"artifact\"}]}}"},{"type":"text","text":"real user text"}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.role, .user)
        XCTAssertEqual(entry?.content, "real user text")
        XCTAssertEqual(entry?.blocks.count, 1)
    }

    func testTimelineEntryDeduplicatesDuplicateStandaloneToolUsesByToolId() {
        let payload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_dup","name":"Read","input":{"file_path":"README.md"}},{"type":"tool_use","id":"tool_dup","name":"Read","input":{"file_path":"docs/README.md"}}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)

        XCTAssertNotNil(entry)
        guard let blocks = entry?.blocks else {
            XCTFail("Expected blocks")
            return
        }

        let toolBlocks = blocks.compactMap { block -> SessionToolUse? in
            guard case .toolUse(let toolUse) = block else { return nil }
            return toolUse
        }

        XCTAssertEqual(toolBlocks.count, 1)
        XCTAssertEqual(toolBlocks.first?.toolUseId, "tool_dup")
        XCTAssertEqual(toolBlocks.first?.summary, "Read docs/README.md")
    }

    func testTimelineEntryParsesToolUseStatusInputAndOutput() {
        let payload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_status_1","name":"Bash","status":"failed","input":{"command":"swift test"},"result":"exit code 1"}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)
        XCTAssertNotNil(entry)

        guard let blocks = entry?.blocks,
              blocks.count == 1,
              case .toolUse(let tool) = blocks[0] else {
            XCTFail("Expected one tool_use block")
            return
        }

        XCTAssertEqual(tool.toolUseId, "tool_status_1")
        XCTAssertEqual(tool.status, .failed)
        XCTAssertEqual(tool.output, "exit code 1")
        XCTAssertNotNil(tool.input)
        XCTAssertTrue(tool.input?.contains("\"command\":\"swift test\"") == true)
    }

    func testTimelineEntryDefaultsToolUseStatusToCompletedWhenMissing() {
        let payload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_status_2","name":"Read","input":{"file_path":"README.md"}}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)
        XCTAssertNotNil(entry)

        guard let blocks = entry?.blocks,
              blocks.count == 1,
              case .toolUse(let tool) = blocks[0] else {
            XCTFail("Expected one tool_use block")
            return
        }

        XCTAssertEqual(tool.toolUseId, "tool_status_2")
        XCTAssertEqual(tool.status, .completed)
        XCTAssertNil(tool.output)
        XCTAssertTrue(tool.input?.contains("\"file_path\":\"README.md\"") == true)
    }

    func testTimelineEntryParsesTaskStatusAndResult() {
        let payload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_status_1","name":"Task","status":"running","input":{"subagent_type":"Explore","description":"Inspect parser contract"},"result":"Investigating payloads"},{"type":"tool_use","id":"task_status_child_1","name":"Grep","status":"failed","parent_tool_use_id":"task_status_1","input":{"pattern":"raw_json"},"result":"grep failed"}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)
        XCTAssertNotNil(entry)

        guard let blocks = entry?.blocks,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one sub-agent activity block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_status_1")
        XCTAssertEqual(activity.status, .running)
        XCTAssertEqual(activity.result, "Investigating payloads")
        XCTAssertEqual(activity.tools.count, 1)
        XCTAssertEqual(activity.tools.first?.toolUseId, "task_status_child_1")
        XCTAssertEqual(activity.tools.first?.status, .failed)
        XCTAssertEqual(activity.tools.first?.output, "grep failed")
    }

    func testTimelineEntryDefaultsTaskStatusToCompletedWhenMissing() {
        let payload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_status_2","name":"Task","input":{"subagent_type":"Explore","description":"Inspect parser contract"}}]}}"#

        let entry = SessionMessagePayloadParser.timelineEntry(from: payload)
        XCTAssertNotNil(entry)

        guard let blocks = entry?.blocks,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one sub-agent activity block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_status_2")
        XCTAssertEqual(activity.status, .completed)
        XCTAssertNil(activity.result)
    }

    func testParseContentBlocksHidesSuccessfulResultAndShowsErrorResult() {
        let success = #"{"type":"result","is_error":false,"result":"ok"}"#
        XCTAssertEqual(SessionMessagePayloadParser.parseContentBlocks(from: success).count, 0)

        let failure = #"{"type":"result","is_error":true,"result":"failed command"}"#
        let blocks = SessionMessagePayloadParser.parseContentBlocks(from: failure)
        XCTAssertEqual(blocks.count, 1)
        guard case .error(let message) = blocks[0] else {
            XCTFail("Expected error block")
            return
        }
        XCTAssertEqual(message, "failed command")
    }

    func testRoleReturnsSystemForUnknownType() {
        let payload = #"{"type":"unknown_type","content":"noop"}"#
        XCTAssertEqual(SessionMessagePayloadParser.role(from: payload), .system)
    }
}
