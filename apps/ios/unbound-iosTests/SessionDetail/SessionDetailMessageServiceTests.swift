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
