import CryptoKit
import Foundation
import XCTest

@testable import unbound_ios

final class SessionDetailMessageServiceTests: XCTestCase {
    func testLoadMessagesDecryptsAndMapsRows() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0x42, count: 32)
        let secret = makeValidSecret(from: keyData)

        let firstPlaintext = #"{"role":"assistant","content":"first"}"#
        let secondPlaintext = #"{"role":"user","content":"second"}"#
        let firstEncrypted = try encrypt(plaintext: firstPlaintext, key: keyData)
        let secondEncrypted = try encrypt(plaintext: secondPlaintext, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "2",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: secondEncrypted.ciphertextB64,
                    contentNonce: secondEncrypted.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: firstEncrypted.ciphertextB64,
                    contentNonce: firstEncrypted.nonceB64
                )
            ]
        )
        let resolver = MockSessionSecretResolver(result: .success(secret))

        let service = SessionDetailMessageService(
            remoteSource: remote,
            secretResolver: resolver
        )

        let result = try await service.loadMessages(sessionId: sessionId)

        XCTAssertEqual(remote.fetchCalls, 1)
        XCTAssertEqual(resolver.calls, 1)
        XCTAssertEqual(result.decryptedMessageCount, 2)
        XCTAssertEqual(result.messages.map(\.content), ["first", "second"])
        XCTAssertEqual(result.messages.map(\.role), [.assistant, .user])
    }

    func testLoadMessagesEmptyRowsSkipsSecretResolution() async throws {
        let remote = MockSessionDetailRemoteSource(rows: [])
        let resolver = MockSessionSecretResolver(result: .success(makeValidSecret(from: Data(repeating: 0x11, count: 32))))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        let result = try await service.loadMessages(sessionId: UUID())

        XCTAssertEqual(result.messages.count, 0)
        XCTAssertEqual(result.decryptedMessageCount, 0)
        XCTAssertEqual(remote.fetchCalls, 1)
        XCTAssertEqual(resolver.calls, 0)
    }

    func testLoadMessagesInvalidCiphertextFailsDeterministically() async {
        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(),
                    contentEncrypted: "not-base64",
                    contentNonce: Data(repeating: 0x00, count: 12).base64EncodedString()
                )
            ]
        )
        let resolver = MockSessionSecretResolver(
            result: .success(makeValidSecret(from: Data(repeating: 0x33, count: 32)))
        )
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        do {
            _ = try await service.loadMessages(sessionId: UUID())
            XCTFail("Expected decrypt failure")
        } catch let error as SessionDetailMessageError {
            XCTAssertEqual(error.errorDescription, SessionDetailMessageError.decryptFailed.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadMessagesSecretResolutionFailureMapsError() async {
        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(),
                    contentEncrypted: Data(repeating: 0xAA, count: 24).base64EncodedString(),
                    contentNonce: Data(repeating: 0xBB, count: 12).base64EncodedString()
                )
            ]
        )
        let resolver = MockSessionSecretResolver(result: .failure(MockFailure.failed))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        do {
            _ = try await service.loadMessages(sessionId: UUID())
            XCTFail("Expected secret resolution failure")
        } catch let error as SessionDetailMessageError {
            XCTAssertEqual(
                error.errorDescription,
                SessionDetailMessageError.secretResolutionFailed.errorDescription
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoadMessagesFiltersProtocolRowsButKeepsDecryptedCount() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0x55, count: 32)
        let secret = makeValidSecret(from: keyData)

        let assistantPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"assistant visible"}]}}"#
        let userToolResultPayload = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool_1","is_error":false}]}}"#
        let successfulResultPayload = #"{"type":"result","is_error":false,"result":"completed"}"#
        let errorResultPayload = #"{"type":"result","is_error":true,"result":"command failed"}"#

        let encryptedAssistant = try encrypt(plaintext: assistantPayload, key: keyData)
        let encryptedToolResult = try encrypt(plaintext: userToolResultPayload, key: keyData)
        let encryptedSuccessResult = try encrypt(plaintext: successfulResultPayload, key: keyData)
        let encryptedErrorResult = try encrypt(plaintext: errorResultPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "4",
                    sequenceNumber: 4,
                    createdAt: Date(timeIntervalSince1970: 40),
                    contentEncrypted: encryptedErrorResult.ciphertextB64,
                    contentNonce: encryptedErrorResult.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "2",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: encryptedToolResult.ciphertextB64,
                    contentNonce: encryptedToolResult.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "3",
                    sequenceNumber: 3,
                    createdAt: Date(timeIntervalSince1970: 30),
                    contentEncrypted: encryptedSuccessResult.ciphertextB64,
                    contentNonce: encryptedSuccessResult.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedAssistant.ciphertextB64,
                    contentNonce: encryptedAssistant.nonceB64
                )
            ]
        )
        let resolver = MockSessionSecretResolver(result: .success(secret))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        let result = try await service.loadMessages(sessionId: sessionId)

        XCTAssertEqual(result.decryptedMessageCount, 4)
        XCTAssertEqual(result.messages.count, 2)
        XCTAssertEqual(result.messages.map(\.content), ["assistant visible", "command failed"])
        XCTAssertEqual(result.messages.map(\.role), [.assistant, .system])
        XCTAssertFalse(result.messages.contains { $0.content == "completed" })
    }

    func testLoadMessagesPreservesUserMessagesWhileHidingToolResultEnvelopes() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0x66, count: 32)
        let secret = makeValidSecret(from: keyData)

        let userTextPayload = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"real user message"}]}}"#
        let userToolResultPayload = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool_1","is_error":false}]}}"#
        let assistantPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"assistant reply"}]}}"#

        let encryptedUserText = try encrypt(plaintext: userTextPayload, key: keyData)
        let encryptedToolResult = try encrypt(plaintext: userToolResultPayload, key: keyData)
        let encryptedAssistant = try encrypt(plaintext: assistantPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "3",
                    sequenceNumber: 3,
                    createdAt: Date(timeIntervalSince1970: 30),
                    contentEncrypted: encryptedAssistant.ciphertextB64,
                    contentNonce: encryptedAssistant.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "2",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: encryptedToolResult.ciphertextB64,
                    contentNonce: encryptedToolResult.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedUserText.ciphertextB64,
                    contentNonce: encryptedUserText.nonceB64
                )
            ]
        )
        let resolver = MockSessionSecretResolver(result: .success(secret))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        let result = try await service.loadMessages(sessionId: sessionId)

        XCTAssertEqual(result.decryptedMessageCount, 3)
        XCTAssertEqual(result.messages.count, 2)
        XCTAssertEqual(result.messages.map(\.content), ["real user message", "assistant reply"])
        XCTAssertEqual(result.messages.map(\.role), [.user, .assistant])
    }

    func testLoadMessagesTreatsPlaintextRowsAsUserMessages() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0x77, count: 32)
        let secret = makeValidSecret(from: keyData)

        let userPlaintext = "please explain this crash"
        let assistantPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Here is the root cause"}]}}"#

        let encryptedUserPlaintext = try encrypt(plaintext: userPlaintext, key: keyData)
        let encryptedAssistant = try encrypt(plaintext: assistantPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "2",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: encryptedAssistant.ciphertextB64,
                    contentNonce: encryptedAssistant.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedUserPlaintext.ciphertextB64,
                    contentNonce: encryptedUserPlaintext.nonceB64
                )
            ]
        )

        let resolver = MockSessionSecretResolver(result: .success(secret))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        let result = try await service.loadMessages(sessionId: sessionId)

        XCTAssertEqual(result.decryptedMessageCount, 2)
        XCTAssertEqual(result.messages.map(\.content), [userPlaintext, "Here is the root cause"])
        XCTAssertEqual(result.messages.map(\.role), [.user, .assistant])
    }

    func testLoadMessagesGroupsSubAgentToolUsesAcrossMessages() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0x88, count: 32)
        let secret = makeValidSecret(from: keyData)

        let taskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"Explore","description":"Search codebase"}}]}}"#
        let childReadPayload = #"{"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_1","name":"Read","input":{"file_path":"README.md"}}]}}"#
        let childGrepPayload = #"{"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_2","name":"Grep","input":{"pattern":"TODO"}}]}}"#

        let encryptedTask = try encrypt(plaintext: taskPayload, key: keyData)
        let encryptedRead = try encrypt(plaintext: childReadPayload, key: keyData)
        let encryptedGrep = try encrypt(plaintext: childGrepPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "3",
                    sequenceNumber: 3,
                    createdAt: Date(timeIntervalSince1970: 30),
                    contentEncrypted: encryptedGrep.ciphertextB64,
                    contentNonce: encryptedGrep.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "2",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: encryptedRead.ciphertextB64,
                    contentNonce: encryptedRead.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedTask.ciphertextB64,
                    contentNonce: encryptedTask.nonceB64
                )
            ]
        )

        let resolver = MockSessionSecretResolver(result: .success(secret))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        let result = try await service.loadMessages(sessionId: sessionId)

        XCTAssertEqual(result.decryptedMessageCount, 3)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.messages.first?.role, .assistant)

        guard let blocks = result.messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one grouped sub-agent block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_1")
        XCTAssertEqual(activity.subagentType, "Explore")
        XCTAssertEqual(activity.tools.count, 2)
        XCTAssertEqual(activity.tools.map(\.toolName), ["Read", "Grep"])
    }

    func testLoadMessagesMergesDuplicateSubAgentActivitiesByParentId() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0x99, count: 32)
        let secret = makeValidSecret(from: keyData)

        let initialTaskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"general-purpose","description":"Initial scan"}}]}}"#
        let updatedTaskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"Plan","description":"Critical review of daemon"}}]}}"#
        let childToolPayload = #"{"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_1","name":"Read","input":{"file_path":"README.md"}}]}}"#

        let encryptedInitialTask = try encrypt(plaintext: initialTaskPayload, key: keyData)
        let encryptedUpdatedTask = try encrypt(plaintext: updatedTaskPayload, key: keyData)
        let encryptedChildTool = try encrypt(plaintext: childToolPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "3",
                    sequenceNumber: 3,
                    createdAt: Date(timeIntervalSince1970: 30),
                    contentEncrypted: encryptedChildTool.ciphertextB64,
                    contentNonce: encryptedChildTool.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "2",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: encryptedUpdatedTask.ciphertextB64,
                    contentNonce: encryptedUpdatedTask.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedInitialTask.ciphertextB64,
                    contentNonce: encryptedInitialTask.nonceB64
                )
            ]
        )

        let resolver = MockSessionSecretResolver(result: .success(secret))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        let result = try await service.loadMessages(sessionId: sessionId)

        XCTAssertEqual(result.decryptedMessageCount, 3)
        XCTAssertEqual(result.messages.count, 1)

        guard let blocks = result.messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one merged sub-agent block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_1")
        XCTAssertEqual(activity.subagentType, "Plan")
        XCTAssertEqual(activity.description, "Critical review of daemon")
        XCTAssertEqual(activity.tools.count, 1)
        XCTAssertEqual(activity.tools.first?.summary, "Read README.md")
    }

    func testLoadMessagesDeduplicatesChildToolUpdatesByToolUseId() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0xAA, count: 32)
        let secret = makeValidSecret(from: keyData)

        let taskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_2","name":"Task","input":{"subagent_type":"Explore","description":"Search codebase"}}]}}"#
        let firstToolPayload = #"{"type":"assistant","parent_tool_use_id":"task_2","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_read","name":"Read","input":{"file_path":"/repo/README.md"}}]}}"#
        let secondToolPayload = #"{"type":"assistant","parent_tool_use_id":"task_2","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_read","name":"Read","input":{"file_path":"/repo/docs/README.md"}}]}}"#

        let encryptedTask = try encrypt(plaintext: taskPayload, key: keyData)
        let encryptedFirstTool = try encrypt(plaintext: firstToolPayload, key: keyData)
        let encryptedSecondTool = try encrypt(plaintext: secondToolPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "3",
                    sequenceNumber: 3,
                    createdAt: Date(timeIntervalSince1970: 30),
                    contentEncrypted: encryptedSecondTool.ciphertextB64,
                    contentNonce: encryptedSecondTool.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "2",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: encryptedFirstTool.ciphertextB64,
                    contentNonce: encryptedFirstTool.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedTask.ciphertextB64,
                    contentNonce: encryptedTask.nonceB64
                )
            ]
        )

        let resolver = MockSessionSecretResolver(result: .success(secret))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        let result = try await service.loadMessages(sessionId: sessionId)

        XCTAssertEqual(result.decryptedMessageCount, 3)
        XCTAssertEqual(result.messages.count, 1)

        guard let blocks = result.messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected one sub-agent block")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_2")
        XCTAssertEqual(activity.tools.count, 1)
        XCTAssertEqual(activity.tools.first?.toolUseId, "tool_read")
        XCTAssertEqual(activity.tools.first?.summary, "Read docs/README.md")
    }

    func testLoadMessagesDeduplicatesInitialRowsByMessageIdWithLatestWriteWins() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0xAB, count: 32)
        let secret = makeValidSecret(from: keyData)

        let olderPayload = #"{"role":"assistant","content":"older"}"#
        let newerPayload = #"{"role":"assistant","content":"newer"}"#
        let trailingPayload = #"{"role":"assistant","content":"tail"}"#

        let encryptedOlder = try encrypt(plaintext: olderPayload, key: keyData)
        let encryptedNewer = try encrypt(plaintext: newerPayload, key: keyData)
        let encryptedTrailing = try encrypt(plaintext: trailingPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "msg-tail",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: encryptedTrailing.ciphertextB64,
                    contentNonce: encryptedTrailing.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "msg-dup",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedOlder.ciphertextB64,
                    contentNonce: encryptedOlder.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "msg-dup",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 30),
                    contentEncrypted: encryptedNewer.ciphertextB64,
                    contentNonce: encryptedNewer.nonceB64
                ),
            ]
        )

        let resolver = MockSessionSecretResolver(result: .success(secret))
        let service = SessionDetailMessageService(remoteSource: remote, secretResolver: resolver)

        let result = try await service.loadMessages(sessionId: sessionId)

        XCTAssertEqual(result.decryptedMessageCount, 2)
        XCTAssertEqual(result.messages.map(\.content), ["newer", "tail"])
    }

    func testMessageUpdatesDecryptsRealtimeEnvelopeAndYieldsGroupedTimeline() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0xBC, count: 32)
        let secret = makeValidSecret(from: keyData)

        let taskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_1","name":"Task","input":{"subagent_type":"Explore","description":"Search codebase"}}]}}"#
        let childToolPayload = #"{"type":"assistant","parent_tool_use_id":"task_1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_1","name":"Read","input":{"file_path":"README.md"}}]}}"#

        let encryptedTask = try encrypt(plaintext: taskPayload, key: keyData)
        let encryptedChildTool = try encrypt(plaintext: childToolPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "1",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedTask.ciphertextB64,
                    contentNonce: encryptedTask.nonceB64
                )
            ]
        )
        let resolver = MockSessionSecretResolver(result: .success(secret))
        let conversationService = MockConversationService()
        let service = SessionDetailMessageService(
            remoteSource: remote,
            secretResolver: resolver,
            conversationService: conversationService
        )

        let stream = service.messageUpdates(sessionId: sessionId)
        let firstUpdateTask = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }

        await conversationService.waitForSubscription()
        conversationService.yield(
            AblyConversationMessageEnvelope(
                schemaVersion: 1,
                sessionId: sessionId.uuidString.lowercased(),
                messageId: "2",
                sequenceNumber: 2,
                senderDeviceId: UUID().uuidString.lowercased(),
                createdAtMs: 20_000,
                encryptionAlg: "chacha20poly1305",
                contentEncrypted: encryptedChildTool.ciphertextB64,
                contentNonce: encryptedChildTool.nonceB64
            )
        )
        conversationService.finish()

        let updateValue = try await firstUpdateTask.value
        let update = try XCTUnwrap(updateValue)
        XCTAssertEqual(update.decryptedMessageCount, 2)
        XCTAssertEqual(update.messages.count, 1)
        XCTAssertEqual(remote.fetchCalls, 1)
        XCTAssertEqual(resolver.calls, 1)

        guard let blocks = update.messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected realtime update to produce grouped sub-agent activity")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_1")
        XCTAssertEqual(activity.tools.count, 1)
        XCTAssertEqual(activity.tools.first?.toolUseId, "tool_1")
    }

    func testMessageUpdatesDeduplicatesRealtimeRowsByMessageID() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0xBD, count: 32)
        let secret = makeValidSecret(from: keyData)

        let firstPayload = #"{"role":"assistant","content":"first"}"#
        let secondPayload = #"{"role":"assistant","content":"second"}"#
        let encryptedFirst = try encrypt(plaintext: firstPayload, key: keyData)
        let encryptedSecond = try encrypt(plaintext: secondPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(rows: [])
        let resolver = MockSessionSecretResolver(result: .success(secret))
        let conversationService = MockConversationService()
        let service = SessionDetailMessageService(
            remoteSource: remote,
            secretResolver: resolver,
            conversationService: conversationService
        )

        let stream = service.messageUpdates(sessionId: sessionId)
        let updatesTask = Task {
            var iterator = stream.makeAsyncIterator()
            var updates: [SessionDetailLoadResult] = []
            while updates.count < 2, let next = try await iterator.next() {
                updates.append(next)
            }
            return updates
        }

        await conversationService.waitForSubscription()
        let senderDeviceID = UUID().uuidString.lowercased()

        conversationService.yield(
            AblyConversationMessageEnvelope(
                schemaVersion: 1,
                sessionId: sessionId.uuidString.lowercased(),
                messageId: "rt-1",
                sequenceNumber: 1,
                senderDeviceId: senderDeviceID,
                createdAtMs: 1_000,
                encryptionAlg: "chacha20poly1305",
                contentEncrypted: encryptedFirst.ciphertextB64,
                contentNonce: encryptedFirst.nonceB64
            )
        )
        conversationService.yield(
            AblyConversationMessageEnvelope(
                schemaVersion: 1,
                sessionId: sessionId.uuidString.lowercased(),
                messageId: "rt-1",
                sequenceNumber: 1,
                senderDeviceId: senderDeviceID,
                createdAtMs: 2_000,
                encryptionAlg: "chacha20poly1305",
                contentEncrypted: encryptedSecond.ciphertextB64,
                contentNonce: encryptedSecond.nonceB64
            )
        )
        conversationService.finish()

        let updates = try await updatesTask.value
        XCTAssertEqual(updates.count, 2)

        XCTAssertEqual(updates[0].decryptedMessageCount, 1)
        XCTAssertEqual(updates[0].messages.map(\.content), ["first"])

        XCTAssertEqual(updates[1].decryptedMessageCount, 1)
        XCTAssertEqual(updates[1].messages.map(\.content), ["second"])
    }

    func testMessageUpdatesConvergesWhenChildToolArrivesBeforeParentTask() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0xBE, count: 32)
        let secret = makeValidSecret(from: keyData)

        let childPayload = #"{"type":"assistant","parent_tool_use_id":"task_early","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_early","name":"Read","input":{"file_path":"README.md"}}]}}"#
        let taskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_early","name":"Task","input":{"subagent_type":"Explore","description":"Trace parser state"}}]}}"#

        let encryptedChild = try encrypt(plaintext: childPayload, key: keyData)
        let encryptedTask = try encrypt(plaintext: taskPayload, key: keyData)

        let remote = MockSessionDetailRemoteSource(rows: [])
        let resolver = MockSessionSecretResolver(result: .success(secret))
        let conversationService = MockConversationService()
        let service = SessionDetailMessageService(
            remoteSource: remote,
            secretResolver: resolver,
            conversationService: conversationService
        )

        let stream = service.messageUpdates(sessionId: sessionId)
        let updatesTask = Task {
            var iterator = stream.makeAsyncIterator()
            var updates: [SessionDetailLoadResult] = []
            while updates.count < 2, let next = try await iterator.next() {
                updates.append(next)
            }
            return updates
        }

        await conversationService.waitForSubscription()
        let senderDeviceID = UUID().uuidString.lowercased()

        conversationService.yield(
            AblyConversationMessageEnvelope(
                schemaVersion: 1,
                sessionId: sessionId.uuidString.lowercased(),
                messageId: "rt-child",
                sequenceNumber: 2,
                senderDeviceId: senderDeviceID,
                createdAtMs: 20_000,
                encryptionAlg: "chacha20poly1305",
                contentEncrypted: encryptedChild.ciphertextB64,
                contentNonce: encryptedChild.nonceB64
            )
        )
        conversationService.yield(
            AblyConversationMessageEnvelope(
                schemaVersion: 1,
                sessionId: sessionId.uuidString.lowercased(),
                messageId: "rt-task",
                sequenceNumber: 1,
                senderDeviceId: senderDeviceID,
                createdAtMs: 10_000,
                encryptionAlg: "chacha20poly1305",
                contentEncrypted: encryptedTask.ciphertextB64,
                contentNonce: encryptedTask.nonceB64
            )
        )
        conversationService.finish()

        let updates = try await updatesTask.value
        XCTAssertEqual(updates.count, 2)

        XCTAssertEqual(updates[0].decryptedMessageCount, 1)
        XCTAssertEqual(updates[0].messages.count, 1)

        XCTAssertEqual(updates[1].decryptedMessageCount, 2)
        XCTAssertEqual(updates[1].messages.count, 1)

        guard let blocks = updates[1].messages.first?.parsedContent,
              blocks.count == 1,
              case .subAgentActivity(let activity) = blocks[0] else {
            XCTFail("Expected converged grouped sub-agent activity")
            return
        }

        XCTAssertEqual(activity.parentToolUseId, "task_early")
        XCTAssertEqual(activity.subagentType, "Explore")
        XCTAssertEqual(activity.tools.count, 1)
        XCTAssertEqual(activity.tools.first?.toolUseId, "tool_early")
    }

    func testInitialLoadAndRealtimeConvergeToSameTimelineForEquivalentRows() async throws {
        let sessionId = UUID()
        let keyData = Data(repeating: 0xBF, count: 32)
        let secret = makeValidSecret(from: keyData)

        let taskPayload = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task_sync","name":"Task","input":{"subagent_type":"Plan","description":"Converge state"}}]}}"#
        let childOlderPayload = #"{"type":"assistant","parent_tool_use_id":"task_sync","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_sync","name":"Read","input":{"file_path":"README.md"}}]}}"#
        let childNewerPayload = #"{"type":"assistant","parent_tool_use_id":"task_sync","message":{"role":"assistant","content":[{"type":"tool_use","id":"tool_sync","name":"Read","input":{"file_path":"docs/README.md"}}]}}"#

        let encryptedTask = try encrypt(plaintext: taskPayload, key: keyData)
        let encryptedChildOlder = try encrypt(plaintext: childOlderPayload, key: keyData)
        let encryptedChildNewer = try encrypt(plaintext: childNewerPayload, key: keyData)

        let loadRemote = MockSessionDetailRemoteSource(
            rows: [
                EncryptedSessionMessageRow(
                    id: "msg-child",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 30),
                    contentEncrypted: encryptedChildNewer.ciphertextB64,
                    contentNonce: encryptedChildNewer.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "msg-task",
                    sequenceNumber: 1,
                    createdAt: Date(timeIntervalSince1970: 10),
                    contentEncrypted: encryptedTask.ciphertextB64,
                    contentNonce: encryptedTask.nonceB64
                ),
                EncryptedSessionMessageRow(
                    id: "msg-child",
                    sequenceNumber: 2,
                    createdAt: Date(timeIntervalSince1970: 20),
                    contentEncrypted: encryptedChildOlder.ciphertextB64,
                    contentNonce: encryptedChildOlder.nonceB64
                ),
            ]
        )

        let loadResolver = MockSessionSecretResolver(result: .success(secret))
        let loadService = SessionDetailMessageService(
            remoteSource: loadRemote,
            secretResolver: loadResolver
        )
        let loadResult = try await loadService.loadMessages(sessionId: sessionId)

        let realtimeRemote = MockSessionDetailRemoteSource(rows: [])
        let realtimeResolver = MockSessionSecretResolver(result: .success(secret))
        let conversationService = MockConversationService()
        let realtimeService = SessionDetailMessageService(
            remoteSource: realtimeRemote,
            secretResolver: realtimeResolver,
            conversationService: conversationService
        )

        let stream = realtimeService.messageUpdates(sessionId: sessionId)
        let updatesTask = Task {
            var iterator = stream.makeAsyncIterator()
            var updates: [SessionDetailLoadResult] = []
            while updates.count < 3, let next = try await iterator.next() {
                updates.append(next)
            }
            return updates
        }

        await conversationService.waitForSubscription()
        let senderDeviceID = UUID().uuidString.lowercased()

        conversationService.yield(
            AblyConversationMessageEnvelope(
                schemaVersion: 1,
                sessionId: sessionId.uuidString.lowercased(),
                messageId: "msg-child",
                sequenceNumber: 2,
                senderDeviceId: senderDeviceID,
                createdAtMs: 20_000,
                encryptionAlg: "chacha20poly1305",
                contentEncrypted: encryptedChildOlder.ciphertextB64,
                contentNonce: encryptedChildOlder.nonceB64
            )
        )
        conversationService.yield(
            AblyConversationMessageEnvelope(
                schemaVersion: 1,
                sessionId: sessionId.uuidString.lowercased(),
                messageId: "msg-task",
                sequenceNumber: 1,
                senderDeviceId: senderDeviceID,
                createdAtMs: 10_000,
                encryptionAlg: "chacha20poly1305",
                contentEncrypted: encryptedTask.ciphertextB64,
                contentNonce: encryptedTask.nonceB64
            )
        )
        conversationService.yield(
            AblyConversationMessageEnvelope(
                schemaVersion: 1,
                sessionId: sessionId.uuidString.lowercased(),
                messageId: "msg-child",
                sequenceNumber: 2,
                senderDeviceId: senderDeviceID,
                createdAtMs: 30_000,
                encryptionAlg: "chacha20poly1305",
                contentEncrypted: encryptedChildNewer.ciphertextB64,
                contentNonce: encryptedChildNewer.nonceB64
            )
        )
        conversationService.finish()

        let updates = try await updatesTask.value
        let realtimeResult = try XCTUnwrap(updates.last)

        XCTAssertEqual(loadResult.decryptedMessageCount, 2)
        XCTAssertEqual(realtimeResult.decryptedMessageCount, 2)
        XCTAssertEqual(
            timelineSignature(loadResult.messages),
            timelineSignature(realtimeResult.messages)
        )
    }

    private func timelineSignature(_ messages: [Message]) -> [String] {
        messages.map { message in
            let blockSignature = (message.parsedContent ?? []).map { block in
                switch block {
                case .text(let text):
                    return "text:\(text)"
                case .error(let message):
                    return "error:\(message)"
                case .toolUse(let tool):
                    return "tool:\(tool.toolUseId ?? "nil"):\(tool.parentToolUseId ?? "nil"):\(tool.toolName):\(tool.summary)"
                case .subAgentActivity(let activity):
                    let tools = activity.tools.map { tool in
                        "\(tool.toolUseId ?? "nil"):\(tool.parentToolUseId ?? "nil"):\(tool.toolName):\(tool.summary)"
                    }.joined(separator: ",")
                    return "subagent:\(activity.parentToolUseId):\(activity.subagentType):\(activity.description):[\(tools)]"
                }
            }.joined(separator: "|")

            return "\(message.role.rawValue)::\(message.content)::\(blockSignature)"
        }
    }

    private func encrypt(plaintext: String, key: Data) throws -> (ciphertextB64: String, nonceB64: String) {
        let symmetricKey = SymmetricKey(data: key)
        let sealed = try ChaChaPoly.seal(Data(plaintext.utf8), using: symmetricKey)

        var ciphertextWithTag = Data()
        ciphertextWithTag.append(sealed.ciphertext)
        ciphertextWithTag.append(sealed.tag)

        let nonceData = sealed.nonce.withUnsafeBytes { Data($0) }
        return (
            ciphertextB64: ciphertextWithTag.base64EncodedString(),
            nonceB64: nonceData.base64EncodedString()
        )
    }

    private func makeValidSecret(from key: Data) -> String {
        var base64Url = key.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while base64Url.hasSuffix("=") {
            base64Url.removeLast()
        }
        return "sess_\(base64Url)"
    }
}

private enum MockFailure: Error {
    case failed
}

private final class MockSessionDetailRemoteSource: SessionDetailMessageRemoteSource {
    private let rows: [EncryptedSessionMessageRow]
    var fetchCalls = 0

    init(rows: [EncryptedSessionMessageRow]) {
        self.rows = rows
    }

    func fetchEncryptedRows(sessionId _: UUID) async throws -> [EncryptedSessionMessageRow] {
        fetchCalls += 1
        return rows
    }
}

private final class MockSessionSecretResolver: SessionSecretResolving {
    private let result: Result<String, Error>
    var calls = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    func joinCodingSession(_ sessionId: UUID) async throws -> String {
        _ = sessionId
        calls += 1
        return try result.get()
    }
}

private final class MockConversationService: SessionDetailConversationStreaming {
    private var continuation: AsyncThrowingStream<AblyConversationMessageEnvelope, Error>.Continuation?

    func subscribe(sessionId _: UUID) -> AsyncThrowingStream<AblyConversationMessageEnvelope, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    func yield(_ envelope: AblyConversationMessageEnvelope) {
        continuation?.yield(envelope)
    }

    func finish() {
        continuation?.finish()
    }

    func waitForSubscription(timeoutNanoseconds: UInt64 = 1_000_000_000) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while continuation == nil {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
