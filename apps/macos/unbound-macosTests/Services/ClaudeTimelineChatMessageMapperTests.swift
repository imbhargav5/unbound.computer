import ClaudeConversationTimeline
import XCTest

@testable import unbound_macos

final class ClaudeTimelineChatMessageMapperTests: XCTestCase {
    func testMapEntriesDropsUserEntryWithProtocolArtifactOnlyText() {
        let entry = ClaudeConversationTimelineEntry(
            id: "user-envelope",
            role: .user,
            blocks: [.text(#"{"type":"assistant","message":{"content":[{"type":"text","text":"artifact"}]}}"#)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "user_prompt_command"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])

        XCTAssertTrue(messages.isEmpty)
    }

    func testMapEntriesDropsUserEntryWithoutVisibleTextBlocks() {
        let tool = ClaudeToolCallBlock(
            toolUseId: "tool-1",
            parentToolUseId: nil,
            name: "Read",
            input: #"{"file_path":"README.md"}"#,
            status: .running,
            resultText: nil
        )
        let entry = ClaudeConversationTimelineEntry(
            id: "user-tool-only",
            role: .user,
            blocks: [.toolCall(tool)],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "user"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])

        XCTAssertTrue(messages.isEmpty)
    }

    func testMapEntriesKeepsUserEntryWithVisibleText() {
        let entry = ClaudeConversationTimelineEntry(
            id: "user-text",
            role: .user,
            blocks: [.text("Please ship this fix.")],
            createdAt: Date(timeIntervalSince1970: 1),
            sequence: 1,
            sourceType: "user_prompt_command"
        )

        let messages = ClaudeTimelineChatMessageMapper.mapEntries([entry])

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.role, .user)
        XCTAssertEqual(messages.first?.textContent, "Please ship this fix.")
    }
}
