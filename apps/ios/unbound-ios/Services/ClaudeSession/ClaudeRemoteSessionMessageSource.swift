import ClaudeConversationTimeline
import Foundation
import Logging

private let claudeRemoteLogger = Logger(label: "app.claude.remote-session-message-source")

final class ClaudeRemoteSessionMessageSource: ClaudeSessionMessageSource {
    private let remoteSource: SessionDetailMessageRemoteSource
    private let secretResolver: SessionSecretResolving
    private let conversationService: SessionDetailConversationStreaming
    private let decryptor = ClaudeSupabaseRowDecryptor()
    private let cache = ClaudeRemoteSessionCache()

    var isDeviceSource: Bool { false }

    init(
        remoteSource: SessionDetailMessageRemoteSource = SupabaseSessionDetailMessageRemoteSource(),
        secretResolver: SessionSecretResolving = CodingSessionViewerService(),
        conversationService: SessionDetailConversationStreaming = AblyConversationService()
    ) {
        self.remoteSource = remoteSource
        self.secretResolver = secretResolver
        self.conversationService = conversationService
    }

    func loadInitial(sessionId: UUID) async throws -> [RawSessionRow] {
        let rows = try await remoteSource.fetchEncryptedRows(sessionId: sessionId)
        let sessionKey = try await resolveSessionKey(sessionId: sessionId)
        let decryptedRows = try decryptor.decryptRows(rows, sessionKey: sessionKey)
        await cache.setSessionKey(sessionKey, for: sessionId)
        return decryptedRows
    }

    func stream(sessionId: UUID) -> AsyncThrowingStream<RawSessionRow, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let sessionKey = try await ensureSessionKey(sessionId: sessionId)

                    for try await envelope in conversationService.subscribe(sessionId: sessionId) {
                        let encryptedRow = ClaudeAblyEnvelopeAdapter.toEncryptedRow(envelope)
                        do {
                            let row = try decryptor.decryptRow(encryptedRow, sessionKey: sessionKey)
                            continuation.yield(row)
                        } catch {
                            claudeRemoteLogger.error(
                                "Failed to decrypt realtime Claude row id=\(encryptedRow.id), seq=\(encryptedRow.sequenceNumber): \(error.localizedDescription)"
                            )
                            continuation.finish(throwing: error)
                            return
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    claudeRemoteLogger.error(
                        "Claude realtime subscription failed for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
                    )
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func ensureSessionKey(sessionId: UUID) async throws -> Data {
        if let cachedSessionKey = await cache.sessionKey(for: sessionId) {
            return cachedSessionKey
        }

        let resolved = try await resolveSessionKey(sessionId: sessionId)
        await cache.setSessionKey(resolved, for: sessionId)
        return resolved
    }

    private func resolveSessionKey(sessionId: UUID) async throws -> Data {
        let sessionSecret: String
        do {
            sessionSecret = try await secretResolver.joinCodingSession(sessionId)
        } catch {
            claudeRemoteLogger.error(
                "Failed to resolve Claude session secret for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
            )
            throw SessionDetailMessageError.secretResolutionFailed
        }

        do {
            return try SessionSecretFormat.parseKey(secret: sessionSecret)
        } catch {
            throw SessionDetailMessageError.secretResolutionFailed
        }
    }
}

private struct ClaudeSupabaseRowDecryptor {
    func decryptRows(_ rows: [EncryptedSessionMessageRow], sessionKey: Data) throws -> [RawSessionRow] {
        try rows.map { try decryptRow($0, sessionKey: sessionKey) }
    }

    func decryptRow(_ row: EncryptedSessionMessageRow, sessionKey: Data) throws -> RawSessionRow {
        let plaintext = try row.decrypt(sessionKey: sessionKey)
        return RawSessionRow(
            id: row.id,
            sequenceNumber: row.sequenceNumber,
            createdAt: row.createdAt,
            updatedAt: nil,
            payload: plaintext
        )
    }
}

private enum ClaudeAblyEnvelopeAdapter {
    static func toEncryptedRow(_ envelope: AblyConversationMessageEnvelope) -> EncryptedSessionMessageRow {
        envelope.toEncryptedRow()
    }
}

private actor ClaudeRemoteSessionCache {
    private var sessionKeyBySession: [UUID: Data] = [:]

    func setSessionKey(_ sessionKey: Data, for sessionId: UUID) {
        sessionKeyBySession[sessionId] = sessionKey
    }

    func sessionKey(for sessionId: UUID) -> Data? {
        sessionKeyBySession[sessionId]
    }
}
