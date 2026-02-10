//
//  SessionDetailMessageService.swift
//  unbound-ios
//
//  Service that loads, decrypts, and maps session detail messages.
//

import Foundation
import Logging

private let sessionDetailServiceLogger = Logger(label: "app.session-detail.service")

protocol SessionSecretResolving {
    func joinCodingSession(_ sessionId: UUID) async throws -> String
}

extension CodingSessionViewerService: SessionSecretResolving {}

struct SessionDetailLoadResult {
    let messages: [Message]
    let decryptedMessageCount: Int
}

protocol SessionDetailMessageLoading {
    func loadMessages(sessionId: UUID) async throws -> SessionDetailLoadResult
}

final class SessionDetailMessageService: SessionDetailMessageLoading {
    private let remoteSource: SessionDetailMessageRemoteSource
    private let secretResolver: SessionSecretResolving

    init(
        remoteSource: SessionDetailMessageRemoteSource = SupabaseSessionDetailMessageRemoteSource(),
        secretResolver: SessionSecretResolving = CodingSessionViewerService()
    ) {
        self.remoteSource = remoteSource
        self.secretResolver = secretResolver
    }

    func loadMessages(sessionId: UUID) async throws -> SessionDetailLoadResult {
        let rows = try await remoteSource.fetchEncryptedRows(sessionId: sessionId)
        sessionDetailServiceLogger.debug(
            "Fetched \(rows.count) encrypted rows for session \(sessionId.uuidString.lowercased())"
        )
        guard !rows.isEmpty else {
            return SessionDetailLoadResult(messages: [], decryptedMessageCount: 0)
        }

        let sessionSecret: String
        do {
            sessionSecret = try await secretResolver.joinCodingSession(sessionId)
        } catch {
            sessionDetailServiceLogger.error(
                "Failed to resolve session secret for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
            )
            throw SessionDetailMessageError.secretResolutionFailed
        }

        let sessionKey: Data
        do {
            sessionKey = try SessionSecretFormat.parseKey(secret: sessionSecret)
        } catch {
            throw SessionDetailMessageError.secretResolutionFailed
        }

        do {
            var mapped: [(sequenceNumber: Int, message: Message)] = []
            mapped.reserveCapacity(rows.count)

            for row in rows {
                let plaintext: String
                do {
                    plaintext = try row.decrypt(sessionKey: sessionKey)
                } catch {
                    sessionDetailServiceLogger.error(
                        "Failed to decrypt row id=\(row.id), seq=\(row.sequenceNumber), session=\(sessionId.uuidString.lowercased()), encrypted_len=\(row.contentEncrypted.count), nonce_len=\(row.contentNonce.count): \(error.localizedDescription)"
                    )
                    throw SessionDetailMessageError.decryptFailed
                }
                mapped.append((
                    sequenceNumber: row.sequenceNumber,
                    message: Message(
                        id: row.stableUUID,
                        content: SessionMessagePayloadParser.displayText(from: plaintext),
                        role: SessionMessagePayloadParser.role(from: plaintext),
                        timestamp: row.createdAt ?? Date(timeIntervalSince1970: 0),
                        isStreaming: false
                    )
                ))
            }

            let sortedMessages = mapped
                .sorted { lhs, rhs in lhs.sequenceNumber < rhs.sequenceNumber }
                .map(\.message)

            return SessionDetailLoadResult(
                messages: sortedMessages,
                decryptedMessageCount: sortedMessages.count
            )
        } catch let error as SessionDetailMessageError {
            sessionDetailServiceLogger.error(
                "Failed during message decrypt/map for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
            )
            throw error
        } catch {
            sessionDetailServiceLogger.error(
                "Failed during message decrypt/map for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
            )
            throw SessionDetailMessageError.payloadParseFailed
        }
    }
}
