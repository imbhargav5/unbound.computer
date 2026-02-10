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
