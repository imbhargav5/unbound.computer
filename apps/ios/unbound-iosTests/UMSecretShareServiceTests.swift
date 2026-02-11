import Foundation
import XCTest

@testable import unbound_ios

final class UMSecretShareServiceTests: XCTestCase {
    func testFetchSessionSecretCacheHitSkipsRemoteFlow() async throws {
        let sessionId = UUID()
        let userId = UUID()
        let context = UMSecretShareService.RequestContext(
            userId: userId,
            requesterDeviceId: UUID().uuidString.lowercased(),
            targetDeviceId: UUID().uuidString.lowercased()
        )
        let cachedSecret = makeValidSecret(byte: 0x11)

        let transport = MockRemoteCommandTransport()
        let decryptor = MockDecryptor(result: .success(makeValidSecret(byte: 0x22)))
        let keyStore = InMemorySessionSecretKeyStore()
        try keyStore.set(secret: cachedSecret, sessionId: sessionId, userId: userId)

        let service = UMSecretShareService(
            transport: transport,
            sessionSecretService: decryptor,
            sessionSecretKeyStore: keyStore
        )

        let secret = try await service.fetchSessionSecret(sessionId: sessionId, context: context)

        XCTAssertEqual(secret, cachedSecret)
        XCTAssertEqual(transport.publishCalls, 0)
        XCTAssertEqual(transport.waitForAckCalls, 0)
        XCTAssertEqual(transport.waitForResponseCalls, 0)
        XCTAssertEqual(decryptor.calls, 0)
    }

    func testFetchSessionSecretCacheMissUsesRemoteAndPersists() async throws {
        let sessionId = UUID()
        let userId = UUID()
        let context = UMSecretShareService.RequestContext(
            userId: userId,
            requesterDeviceId: UUID().uuidString.lowercased(),
            targetDeviceId: UUID().uuidString.lowercased()
        )

        let expectedSecret = makeValidSecret(byte: 0x33)
        let transport = MockRemoteCommandTransport()
        let decryptor = MockDecryptor(result: .success(expectedSecret))
        let keyStore = InMemorySessionSecretKeyStore()

        let service = UMSecretShareService(
            transport: transport,
            sessionSecretService: decryptor,
            sessionSecretKeyStore: keyStore
        )

        let secret = try await service.fetchSessionSecret(sessionId: sessionId, context: context)

        XCTAssertEqual(secret, expectedSecret)
        XCTAssertEqual(transport.publishCalls, 1)
        XCTAssertEqual(transport.waitForAckCalls, 1)
        XCTAssertEqual(transport.waitForResponseCalls, 1)
        XCTAssertEqual(decryptor.calls, 1)
        XCTAssertEqual(try keyStore.get(sessionId: sessionId, userId: userId), expectedSecret)
    }

    func testFetchSessionSecretRemoteTimeoutSurfacesError() async {
        let sessionId = UUID()
        let userId = UUID()
        let context = UMSecretShareService.RequestContext(
            userId: userId,
            requesterDeviceId: UUID().uuidString.lowercased(),
            targetDeviceId: UUID().uuidString.lowercased()
        )

        let transport = MockRemoteCommandTransport()
        transport.ackError = RemoteCommandTransportError.timeout

        let decryptor = MockDecryptor(result: .success(makeValidSecret(byte: 0x44)))
        let keyStore = InMemorySessionSecretKeyStore()

        let service = UMSecretShareService(
            transport: transport,
            sessionSecretService: decryptor,
            sessionSecretKeyStore: keyStore
        )

        do {
            _ = try await service.fetchSessionSecret(sessionId: sessionId, context: context)
            XCTFail("Expected timeout error")
        } catch let error as UMSecretShareError {
            guard case .timeout = error else {
                XCTFail("Unexpected UMSecretShareError: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(transport.publishCalls, 1)
        XCTAssertEqual(transport.waitForAckCalls, 1)
        XCTAssertNil(try? keyStore.get(sessionId: sessionId, userId: userId))
    }

    private func makeValidSecret(byte: UInt8) -> String {
        let data = Data(repeating: byte, count: 32)
        var base64Url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while base64Url.hasSuffix("=") {
            base64Url.removeLast()
        }
        return "sess_\(base64Url)"
    }
}

private final class InMemorySessionSecretKeyStore: SessionSecretKeyStoring {
    private var values: [String: String] = [:]

    func get(sessionId: UUID, userId: UUID) throws -> String? {
        values[key(sessionId: sessionId, userId: userId)]
    }

    func set(secret: String, sessionId: UUID, userId: UUID) throws {
        values[key(sessionId: sessionId, userId: userId)] = secret
    }

    func delete(sessionId: UUID, userId: UUID) throws {
        values.removeValue(forKey: key(sessionId: sessionId, userId: userId))
    }

    private func key(sessionId: UUID, userId: UUID) -> String {
        "\(sessionId.uuidString.lowercased())::\(userId.uuidString.lowercased())"
    }
}

private final class MockDecryptor: SessionSecretEnvelopeDecrypting {
    var calls = 0
    var result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func decryptCodingSessionSecretEnvelope(
        encapsulationPublicKey _: String,
        nonceB64 _: String,
        ciphertextB64 _: String,
        sessionId _: UUID,
        userId _: String
    ) throws -> String {
        calls += 1
        return try result.get()
    }
}

private final class MockRemoteCommandTransport: RemoteCommandTransport {
    var publishCalls = 0
    var waitForAckCalls = 0
    var waitForResponseCalls = 0

    var publishError: Error?
    var ackError: Error?
    var responseError: Error?

    var ackStatus = "accepted"
    var decisionStatus = "accepted"
    var decisionReasonCode: String?
    var decisionMessage = "accepted"

    var responseStatus = "ok"
    var responseErrorCode: String?
    var responseCiphertextB64 = Data("ciphertext".utf8).base64EncodedString()
    var responseEncapsulationPubkeyB64 = Data(repeating: 0xAA, count: 32).base64EncodedString()
    var responseNonceB64 = Data(repeating: 0xBB, count: 12).base64EncodedString()

    func publishRemoteCommand(
        channel _: String,
        payload _: UMSecretRequestCommandPayload
    ) async throws {
        publishCalls += 1
        if let publishError {
            throw publishError
        }
    }

    func waitForAck(
        channel _: String,
        requestId: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandAckEnvelope {
        waitForAckCalls += 1
        if let ackError {
            throw ackError
        }

        let decision = RemoteCommandDecisionResult(
            schemaVersion: 1,
            requestId: requestId,
            sessionId: nil,
            status: decisionStatus,
            reasonCode: decisionReasonCode,
            message: decisionMessage
        )
        let encoded = try JSONEncoder().encode(decision).base64EncodedString()

        return RemoteCommandAckEnvelope(
            schemaVersion: 1,
            commandId: UUID().uuidString.lowercased(),
            status: ackStatus,
            createdAtMs: 1,
            resultB64: encoded
        )
    }

    func waitForSessionSecretResponse(
        channel _: String,
        requestId: String,
        sessionId: String,
        timeout _: TimeInterval
    ) async throws -> SessionSecretResponseEnvelope {
        waitForResponseCalls += 1
        if let responseError {
            throw responseError
        }

        return SessionSecretResponseEnvelope(
            schemaVersion: 1,
            requestId: requestId,
            sessionId: sessionId,
            senderDeviceId: UUID().uuidString.lowercased(),
            receiverDeviceId: UUID().uuidString.lowercased(),
            status: responseStatus,
            errorCode: responseErrorCode,
            ciphertextB64: responseStatus == "ok" ? responseCiphertextB64 : nil,
            encapsulationPubkeyB64: responseStatus == "ok" ? responseEncapsulationPubkeyB64 : nil,
            nonceB64: responseStatus == "ok" ? responseNonceB64 : nil,
            algorithm: "x25519-hkdf-sha256-chacha20poly1305",
            createdAtMs: 1
        )
    }

    func publishGenericCommand(
        channel _: String,
        envelope _: RemoteCommandEnvelope
    ) async throws {
        publishCalls += 1
        if let publishError {
            throw publishError
        }
    }

    func waitForCommandResponse(
        channel _: String,
        requestId: String,
        timeout _: TimeInterval
    ) async throws -> RemoteCommandResponse {
        return RemoteCommandResponse(
            schemaVersion: 1,
            requestId: requestId,
            type: "mock.v1",
            status: "ok",
            result: nil,
            errorCode: nil,
            errorMessage: nil,
            createdAtMs: 1
        )
    }
}
