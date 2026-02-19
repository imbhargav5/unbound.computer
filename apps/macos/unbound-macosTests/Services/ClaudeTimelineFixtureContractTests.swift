import Foundation
import ClaudeConversationTimeline
import XCTest

final class ClaudeTimelineFixtureContractTests: XCTestCase {
    func testSharedClaudeFixturesParse() throws {
        let fixtureURL = try sharedFixtureURL()
        let data = try Data(contentsOf: fixtureURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])

        for fixtureCase in cases {
            let parser = ClaudeConversationTimelineParser()
            let events = fixtureCase["events"] as? [Any] ?? []

            for event in events {
                let eventData = try JSONSerialization.data(withJSONObject: event)
                let jsonString = try XCTUnwrap(String(data: eventData, encoding: .utf8))
                parser.ingest(rawJSON: jsonString)
            }

            let entries = parser.currentTimeline()
            let roles = Set(entries.map { $0.role.rawValue })
            let blockTypes = Set(entries.flatMap { entry in
                entry.blocks.map(blockTypeName)
            })

            let expectations = fixtureCase["expect"] as? [String: Any]
            let expectedRoles = expectations?["roles"] as? [String] ?? []
            let expectedBlocks = expectations?["blockTypes"] as? [String] ?? []
            let expectedEntryCount = expectations?["entryCount"] as? Int

            if let expectedEntryCount {
                XCTAssertEqual(
                    entries.count,
                    expectedEntryCount,
                    "Expected entryCount \(expectedEntryCount) in fixture \(fixtureCase["id"] as? String ?? "unknown")"
                )
            }

            for role in expectedRoles {
                XCTAssertTrue(roles.contains(role), "Expected role \(role) in fixture \(fixtureCase["id"] as? String ?? "unknown")")
            }

            for block in expectedBlocks {
                XCTAssertTrue(blockTypes.contains(block), "Expected block \(block) in fixture \(fixtureCase["id"] as? String ?? "unknown")")
            }
        }
    }

    func testCodingSessionStateIngestsPlainTextRowAsUserMessage() throws {
        let state = ClaudeCodingSessionState(source: EmptySessionMessageSource())
        let row = RawSessionRow(
            id: "plain-row-1",
            sequenceNumber: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: nil,
            payload: "plain text payload"
        )

        state.ingest(rows: [row])

        XCTAssertEqual(state.timeline.count, 1)
        let entry = try XCTUnwrap(state.timeline.first)
        XCTAssertEqual(entry.id, "plain-row-1")
        XCTAssertEqual(entry.role, .user)
        XCTAssertEqual(entry.blocks.count, 1)
        guard case .text(let text) = entry.blocks[0] else {
            return XCTFail("Expected text block for plain payload")
        }
        XCTAssertEqual(text, "plain text payload")
    }

    func testCodingSessionStateKeepsDistinctPlainTextRowsById() {
        let state = ClaudeCodingSessionState(source: EmptySessionMessageSource())
        let first = RawSessionRow(
            id: "plain-row-a",
            sequenceNumber: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: nil,
            payload: "same text"
        )
        let second = RawSessionRow(
            id: "plain-row-b",
            sequenceNumber: 2,
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: nil,
            payload: "same text"
        )

        state.ingest(rows: [first, second])

        XCTAssertEqual(state.timeline.count, 2)
        XCTAssertEqual(state.timeline.map(\.id), ["plain-row-a", "plain-row-b"])
        XCTAssertTrue(state.timeline.allSatisfy { $0.role == .user })
    }

    func testParserSuppressesUserToolUseEnvelope() throws {
        let parser = ClaudeConversationTimelineParser()
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_use",
                        "id": "tool_1",
                        "name": "Read",
                        "input": ["file_path": "README.md"]
                    ],
                ],
            ],
        ]
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8))

        parser.ingest(rawJSON: json)

        XCTAssertTrue(parser.currentTimeline().isEmpty)
    }

    func testParserSuppressesUserPromptCommandWithSerializedEnvelope() throws {
        let parser = ClaudeConversationTimelineParser()
        let envelope = #"{"type":"user","message":{"content":[{"type":"tool_use","id":"tool_1","name":"Read"}]}}"#
        let payload: [String: Any] = [
            "type": "user_prompt_command",
            "message": envelope,
        ]
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8))

        parser.ingest(rawJSON: json)

        XCTAssertTrue(parser.currentTimeline().isEmpty)
    }

    func testParserSuppressesUserToolResultEnvelopeEvenWithTextContent() throws {
        let parser = ClaudeConversationTimelineParser()
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": "tool_1",
                        "content": "Read README.md"
                    ],
                ],
            ],
        ]
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8))

        parser.ingest(rawJSON: json)

        XCTAssertTrue(parser.currentTimeline().isEmpty)
    }

    func testParserSuppressesTopLevelUserSerializedEnvelopeStringPayload() throws {
        let parser = ClaudeConversationTimelineParser()
        let payload: [String: Any] = [
            "type": "user",
            "message": #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool_1","name":"Read"}]}}"#
        ]
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8))

        parser.ingest(rawJSON: json)

        XCTAssertTrue(parser.currentTimeline().isEmpty)
    }

    func testParserShowsTopLevelUserStringPayload() throws {
        let parser = ClaudeConversationTimelineParser()
        let payload: [String: Any] = [
            "type": "user",
            "message": "actual user text",
        ]
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8))

        parser.ingest(rawJSON: json)

        XCTAssertEqual(parser.currentTimeline().count, 1)
        let entry = try XCTUnwrap(parser.currentTimeline().first)
        XCTAssertEqual(entry.role, .user)
        guard case .text(let text) = entry.blocks.first else {
            return XCTFail("Expected text block")
        }
        XCTAssertEqual(text, "actual user text")
    }

    func testParserSuppressesUserTextWithParentToolUseId() throws {
        let parser = ClaudeConversationTimelineParser()
        let payload: [String: Any] = [
            "type": "user",
            "parent_tool_use_id": "tool_parent_1",
            "message": [
                "content": [
                    [
                        "type": "text",
                        "text": "Find files related to crypto",
                    ],
                ],
            ],
        ]
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8))

        parser.ingest(rawJSON: json)

        XCTAssertTrue(parser.currentTimeline().isEmpty)
    }

    func testParserShowsUserPromptCommandPlainText() throws {
        let parser = ClaudeConversationTimelineParser()
        let payload: [String: Any] = [
            "type": "user_prompt_command",
            "message": "Ship this fix now",
        ]
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8))

        parser.ingest(rawJSON: json)

        XCTAssertEqual(parser.currentTimeline().count, 1)
        let entry = try XCTUnwrap(parser.currentTimeline().first)
        XCTAssertEqual(entry.role, .user)
        XCTAssertEqual(entry.sourceType, "user_prompt_command")
        guard case .text(let text) = entry.blocks.first else {
            return XCTFail("Expected text block")
        }
        XCTAssertEqual(text, "Ship this fix now")
    }

    func testCodingSessionStateSuppressesProtocolEnvelopeLikePlainTextRow() {
        let state = ClaudeCodingSessionState(source: EmptySessionMessageSource())
        let row = RawSessionRow(
            id: "plain-envelope-row",
            sequenceNumber: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: nil,
            payload: #"{"type":"user","message":{"content":[{"type":"tool_use","id":"tool_1","name":"Read"}]}"#
        )

        state.ingest(rows: [row])

        XCTAssertTrue(state.timeline.isEmpty)
    }

    func testCodingSessionStateAllowsBracePrefixedNonProtocolText() throws {
        let state = ClaudeCodingSessionState(source: EmptySessionMessageSource())
        let row = RawSessionRow(
            id: "brace-text-row",
            sequenceNumber: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: nil,
            payload: "{this is not protocol envelope text}"
        )

        state.ingest(rows: [row])

        XCTAssertEqual(state.timeline.count, 1)
        let entry = try XCTUnwrap(state.timeline.first)
        XCTAssertEqual(entry.role, .user)
        guard case .text(let text) = entry.blocks.first else {
            return XCTFail("Expected text block")
        }
        XCTAssertEqual(text, "{this is not protocol envelope text}")
    }

    func testParserOrdersEntriesUsingStringSequenceMetadata() throws {
        let parser = ClaudeConversationTimelineParser()

        let assistantPayload: [String: Any] = [
            "id": "a-assistant",
            "type": "assistant",
            "sequence_number": "2",
            "message": [
                "content": [
                    [
                        "type": "text",
                        "text": "Assistant response",
                    ],
                ],
            ],
        ]

        let userPayload: [String: Any] = [
            "id": "z-user",
            "type": "user",
            "sequence_number": "1",
            "message": "User prompt",
        ]

        parser.ingest(payload: assistantPayload)
        parser.ingest(payload: userPayload)

        let entries = parser.currentTimeline()
        XCTAssertEqual(entries.map(\.id), ["z-user", "a-assistant"])
        XCTAssertEqual(entries.map(\.role), [.user, .assistant])
    }

    func testAssistantSameIdTextThenToolUseRetainsTextAndTool() throws {
        let parser = ClaudeConversationTimelineParser()

        let textPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_same_id_merge",
                "content": [
                    [
                        "type": "text",
                        "text": "I'll create 3 explore agents in parallel.",
                    ],
                ],
            ],
        ]

        let toolPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_same_id_merge",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "tool_same_id_read",
                        "name": "Read",
                        "input": ["file_path": "README.md"],
                    ],
                ],
            ],
        ]

        parser.ingest(payload: textPayload)
        parser.ingest(payload: toolPayload)

        let entries = parser.currentTimeline()
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.role, .assistant)

        let visibleText = entry.blocks.compactMap { block -> String? in
            guard case .text(let text) = block else { return nil }
            return text
        }
        XCTAssertEqual(visibleText, ["I'll create 3 explore agents in parallel."])

        let toolCalls = entry.blocks.compactMap { block -> ClaudeToolCallBlock? in
            guard case .toolCall(let tool) = block else { return nil }
            return tool
        }
        XCTAssertEqual(toolCalls.map(\.toolUseId), ["tool_same_id_read"])
        XCTAssertEqual(toolCalls.map(\.name), ["Read"])
    }

    func testAssistantSameIdLatestNonEmptyTextWins() throws {
        let parser = ClaudeConversationTimelineParser()

        let firstPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_same_id_text_update",
                "content": [
                    [
                        "type": "text",
                        "text": "First commentary",
                    ],
                ],
            ],
        ]

        let secondPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_same_id_text_update",
                "content": [
                    [
                        "type": "text",
                        "text": "Second commentary",
                    ],
                ],
            ],
        ]

        parser.ingest(payload: firstPayload)
        parser.ingest(payload: secondPayload)

        let entry = try XCTUnwrap(parser.currentTimeline().first)
        let visibleText = entry.blocks.compactMap { block -> String? in
            guard case .text(let text) = block else { return nil }
            return text
        }
        XCTAssertEqual(visibleText, ["Second commentary"])
    }

    func testSystemInitRemainsSuppressed() {
        let parser = ClaudeConversationTimelineParser()
        let payload: [String: Any] = [
            "type": "system",
            "subtype": "init",
            "model": "claude-opus-4-5-20251101",
        ]

        parser.ingest(payload: payload)

        XCTAssertTrue(parser.currentTimeline().isEmpty)
    }

    func testParserTaskToolResultUpdatesSubAgentStatus() throws {
        let parser = ClaudeConversationTimelineParser()

        let assistantTaskPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_task_status",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "task_status",
                        "name": "Task",
                        "input": [
                            "subagent_type": "Explore",
                            "description": "Inspect daemon structure",
                        ],
                    ],
                ],
            ],
        ]
        let toolResultPayload: [String: Any] = [
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": "task_status",
                        "is_error": false,
                        "content": "Sub-agent done",
                    ],
                ],
            ],
        ]

        parser.ingest(payload: assistantTaskPayload)
        parser.ingest(payload: toolResultPayload)

        let entry = try XCTUnwrap(parser.currentTimeline().first(where: { $0.id == "msg_task_status" }))
        let subAgent = try XCTUnwrap(entry.blocks.compactMap { block -> ClaudeSubAgentBlock? in
            guard case .subAgent(let value) = block else { return nil }
            return value
        }.first)

        XCTAssertEqual(subAgent.status, .completed)
        XCTAssertEqual(subAgent.result, "Sub-agent done")
    }

    func testParserTaskToolResultArrayContentUpdatesSubAgentResult() throws {
        let parser = ClaudeConversationTimelineParser()

        let assistantTaskPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_task_array_result",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "task_array_result",
                        "name": "Task",
                        "input": [
                            "subagent_type": "Explore",
                            "description": "Inspect daemon structure",
                        ],
                    ],
                ],
            ],
        ]
        let toolResultPayload: [String: Any] = [
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": "task_array_result",
                        "is_error": false,
                        "content": [
                            [
                                "type": "text",
                                "text": "Found issues in daemon lifecycle.",
                            ],
                            [
                                "type": "text",
                                "text": "agentId: a12ae7a",
                            ],
                        ],
                    ],
                ],
            ],
        ]

        parser.ingest(payload: assistantTaskPayload)
        parser.ingest(payload: toolResultPayload)

        let entry = try XCTUnwrap(parser.currentTimeline().first(where: { $0.id == "msg_task_array_result" }))
        let subAgent = try XCTUnwrap(entry.blocks.compactMap { block -> ClaudeSubAgentBlock? in
            guard case .subAgent(let value) = block else { return nil }
            return value
        }.first)

        XCTAssertEqual(subAgent.status, .completed)
        XCTAssertEqual(subAgent.result, "Found issues in daemon lifecycle.\nagentId: a12ae7a")
    }

    func testParserChildToolResultArrayContentUpdatesToolOutput() throws {
        let parser = ClaudeConversationTimelineParser()

        let parentTaskPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_task_parent",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "task_parent",
                        "name": "Task",
                        "input": [
                            "subagent_type": "Explore",
                            "description": "Inspect files",
                        ],
                    ],
                ],
            ],
        ]
        let childToolPayload: [String: Any] = [
            "type": "assistant",
            "parent_tool_use_id": "task_parent",
            "message": [
                "id": "msg_task_child",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "tool_child_array",
                        "name": "Bash",
                        "input": [
                            "command": "echo hello",
                        ],
                    ],
                ],
            ],
        ]
        let childToolResultPayload: [String: Any] = [
            "type": "user",
            "message": [
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": "tool_child_array",
                        "is_error": false,
                        "content": [
                            [
                                "type": "text",
                                "text": "stdout line 1",
                            ],
                            [
                                "type": "text",
                                "text": "stdout line 2",
                            ],
                        ],
                    ],
                ],
            ],
        ]

        parser.ingest(payload: parentTaskPayload)
        parser.ingest(payload: childToolPayload)
        parser.ingest(payload: childToolResultPayload)

        let childEntry = try XCTUnwrap(parser.currentTimeline().first(where: { $0.id == "msg_task_child" }))
        let childTool = try XCTUnwrap(childEntry.blocks.compactMap { block -> ClaudeToolCallBlock? in
            guard case .toolCall(let value) = block else { return nil }
            return value
        }.first(where: { $0.toolUseId == "tool_child_array" }))

        XCTAssertEqual(childTool.status, .completed)
        XCTAssertEqual(childTool.resultText, "stdout line 1\nstdout line 2")
    }

    func testParserResultFinalizesResidualRunningStates() {
        let parser = ClaudeConversationTimelineParser()

        let standaloneToolPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_running_tool",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "tool_running",
                        "name": "Read",
                        "input": ["file_path": "README.md"],
                    ],
                ],
            ],
        ]
        let taskPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_running_task",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "task_running",
                        "name": "Task",
                        "input": [
                            "subagent_type": "Explore",
                            "description": "Inspect files",
                        ],
                    ],
                ],
            ],
        ]
        let childToolPayload: [String: Any] = [
            "type": "assistant",
            "message": [
                "id": "msg_running_child",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "child_running",
                        "name": "Grep",
                        "parent_tool_use_id": "task_running",
                        "input": ["pattern": "TODO"],
                    ],
                ],
            ],
        ]
        let resultPayload: [String: Any] = [
            "type": "result",
            "is_error": false,
            "result": "Done",
        ]

        parser.ingest(payload: standaloneToolPayload)
        parser.ingest(payload: taskPayload)
        parser.ingest(payload: childToolPayload)
        parser.ingest(payload: resultPayload)

        let statuses: [ClaudeToolCallStatus] = parser.currentTimeline().flatMap { entry in
            entry.blocks.flatMap { block -> [ClaudeToolCallStatus] in
                switch block {
                case .toolCall(let tool):
                    return [tool.status]
                case .subAgent(let subAgent):
                    return [subAgent.status] + subAgent.tools.map(\.status)
                default:
                    return []
                }
            }
        }

        XCTAssertFalse(statuses.isEmpty)
        XCTAssertFalse(statuses.contains(.running))
        XCTAssertTrue(statuses.allSatisfy { $0 == .completed })
    }

    func testParserOrdersEntriesUsingFractionalCreatedAt() throws {
        let parser = ClaudeConversationTimelineParser()

        let assistantPayload: [String: Any] = [
            "id": "a-assistant-date",
            "type": "assistant",
            "created_at": "2026-02-18T10:00:01.123456+00:00",
            "message": [
                "content": [
                    [
                        "type": "text",
                        "text": "Assistant response",
                    ],
                ],
            ],
        ]

        let userPayload: [String: Any] = [
            "id": "z-user-date",
            "type": "user",
            "created_at": "2026-02-18T10:00:00.123456+00:00",
            "message": "User prompt",
        ]

        parser.ingest(payload: assistantPayload)
        parser.ingest(payload: userPayload)

        let entries = parser.currentTimeline()
        XCTAssertEqual(entries.map(\.id), ["z-user-date", "a-assistant-date"])
        XCTAssertEqual(entries.map(\.role), [.user, .assistant])
    }

    func testCodingSessionStateBackfillsRowIdForIdlessJSONPayloads() throws {
        let state = ClaudeCodingSessionState(source: EmptySessionMessageSource())

        let rowUser = RawSessionRow(
            id: "row-user",
            sequenceNumber: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: nil,
            payload: #"{"type":"user","message":"First user message"}"#
        )

        let rowAssistant = RawSessionRow(
            id: "row-assistant",
            sequenceNumber: 2,
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: nil,
            payload: #"{"type":"assistant","message":{"content":[{"type":"text","text":"Assistant reply"}]}}"#
        )

        state.ingest(rows: [rowAssistant, rowUser])

        XCTAssertEqual(state.timeline.map(\.id), ["row-user", "row-assistant"])
        XCTAssertEqual(state.timeline.map(\.role), [.user, .assistant])
    }

    func testCodingSessionStateRetainsAssistantSameMessageIdUpdatesForMerge() throws {
        let state = ClaudeCodingSessionState(source: EmptySessionMessageSource())

        let first = RawSessionRow(
            id: "assistant-row-1",
            sequenceNumber: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: nil,
            payload: #"{"type":"assistant","message":{"id":"msg_shared","content":[{"type":"text","text":"I'll create 3 explore agents in parallel."}]}}"#
        )

        let second = RawSessionRow(
            id: "assistant-row-2",
            sequenceNumber: 2,
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: nil,
            payload: #"{"type":"assistant","message":{"id":"msg_shared","content":[{"type":"tool_use","id":"tool_shared","name":"Read","input":{"file_path":"README.md"}}]}}"#
        )

        state.ingest(rows: [first, second])

        XCTAssertEqual(state.timeline.count, 1)
        let entry = try XCTUnwrap(state.timeline.first)
        XCTAssertEqual(entry.role, .assistant)

        let textBlocks = entry.blocks.compactMap { block -> String? in
            guard case .text(let text) = block else { return nil }
            return text
        }
        XCTAssertEqual(textBlocks, ["I'll create 3 explore agents in parallel."])

        let tools = entry.blocks.compactMap { block -> ClaudeToolCallBlock? in
            guard case .toolCall(let tool) = block else { return nil }
            return tool
        }
        XCTAssertEqual(tools.map(\.toolUseId), ["tool_shared"])
        XCTAssertEqual(tools.map(\.name), ["Read"])
    }

    private func sharedFixtureURL() throws -> URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        let baseURL = fileURL.deletingLastPathComponent()
        let fixturePath = baseURL
            .appendingPathComponent("../../../shared/ClaudeConversationTimeline/Fixtures/claude-parser-contract-fixtures.json")
            .standardizedFileURL
        if !FileManager.default.fileExists(atPath: fixturePath.path) {
            throw XCTSkip("Shared fixture not found at \(fixturePath.path)")
        }
        return fixturePath
    }

    private func blockTypeName(_ block: ClaudeConversationBlock) -> String {
        switch block {
        case .text:
            return "text"
        case .toolCall:
            return "toolCall"
        case .subAgent:
            return "subAgent"
        case .compactBoundary:
            return "compactBoundary"
        case .result:
            return "result"
        case .error:
            return "error"
        case .unknown:
            return "unknown"
        }
    }
}

private struct EmptySessionMessageSource: ClaudeSessionMessageSource {
    var isDeviceSource: Bool { true }

    func loadInitial(sessionId: UUID) async throws -> [RawSessionRow] {
        []
    }

    func stream(sessionId: UUID) -> AsyncThrowingStream<RawSessionRow, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
