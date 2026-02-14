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
    func messageUpdates(sessionId: UUID) -> AsyncThrowingStream<SessionDetailLoadResult, Error>
}

final class SessionDetailMessageService: SessionDetailMessageLoading {
    private let remoteSource: SessionDetailMessageRemoteSource
    private let secretResolver: SessionSecretResolving
    private let conversationService: SessionDetailConversationStreaming
    private let cache = SessionDetailMessageCache()

    init(
        remoteSource: SessionDetailMessageRemoteSource = SupabaseSessionDetailMessageRemoteSource(),
        secretResolver: SessionSecretResolving = CodingSessionViewerService(),
        conversationService: SessionDetailConversationStreaming = AblyConversationService()
    ) {
        self.remoteSource = remoteSource
        self.secretResolver = secretResolver
        self.conversationService = conversationService
    }

    func loadMessages(sessionId: UUID) async throws -> SessionDetailLoadResult {
        let rows = try await remoteSource.fetchEncryptedRows(sessionId: sessionId)
        sessionDetailServiceLogger.debug(
            "Fetched \(rows.count) encrypted rows for session \(sessionId.uuidString.lowercased())"
        )
        let normalizedRows = await cache.setRows(rows, for: sessionId)

        guard !normalizedRows.isEmpty else {
            return SessionDetailLoadResult(messages: [], decryptedMessageCount: 0)
        }

        let sessionKey = try await resolveSessionKey(sessionId: sessionId)
        await cache.setSessionKey(sessionKey, for: sessionId)
        return try decryptAndMap(
            rows: normalizedRows,
            sessionKey: sessionKey,
            sessionId: sessionId
        )
    }

    func messageUpdates(sessionId: UUID) -> AsyncThrowingStream<SessionDetailLoadResult, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let sessionKey = try await ensureSessionKey(sessionId: sessionId)
                    _ = try await ensureSeedRows(sessionId: sessionId)

                    for try await envelope in conversationService.subscribe(sessionId: sessionId) {
                        let mergedRows = await cache.upsert(
                            envelope.toEncryptedRow(),
                            for: sessionId
                        )

                        do {
                            let result = try decryptAndMap(
                                rows: mergedRows,
                                sessionKey: sessionKey,
                                sessionId: sessionId
                            )
                            continuation.yield(result)
                        } catch let error as SessionDetailMessageError {
                            sessionDetailServiceLogger.error(
                                "Ignoring realtime session payload for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
                            )
                        } catch {
                            sessionDetailServiceLogger.error(
                                "Ignoring realtime session payload for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
                            )
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    sessionDetailServiceLogger.error(
                        "Session detail realtime subscription failed for session \(sessionId.uuidString.lowercased()): \(error.localizedDescription)"
                    )
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func ensureSeedRows(sessionId: UUID) async throws -> [EncryptedSessionMessageRow] {
        if let cachedRows = await cache.cachedRows(for: sessionId) {
            return cachedRows
        }

        let rows = try await remoteSource.fetchEncryptedRows(sessionId: sessionId)
        await cache.setRows(rows, for: sessionId)
        return rows
    }

    private func ensureSessionKey(sessionId: UUID) async throws -> Data {
        if let cachedSessionKey = await cache.sessionKey(for: sessionId) {
            return cachedSessionKey
        }

        let resolvedSessionKey = try await resolveSessionKey(sessionId: sessionId)
        await cache.setSessionKey(resolvedSessionKey, for: sessionId)
        return resolvedSessionKey
    }

    private func resolveSessionKey(sessionId: UUID) async throws -> Data {
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

        return sessionKey
    }

    private func decryptAndMap(
        rows: [EncryptedSessionMessageRow],
        sessionKey: Data,
        sessionId: UUID
    ) throws -> SessionDetailLoadResult {
        do {
            var plaintextRows: [SessionDetailPlaintextMessageRow] = []
            plaintextRows.reserveCapacity(rows.count)

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

                plaintextRows.append(
                    SessionDetailPlaintextMessageRow(
                        id: row.id,
                        sequenceNumber: row.sequenceNumber,
                        createdAt: row.createdAt,
                        content: plaintext
                    )
                )
            }

            return SessionDetailMessageMapper.mapRows(
                plaintextRows,
                totalMessageCount: rows.count
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

private actor SessionDetailMessageCache {
    private var rowsBySession: [UUID: [EncryptedSessionMessageRow]] = [:]
    private var sessionKeyBySession: [UUID: Data] = [:]

    @discardableResult
    func setRows(_ rows: [EncryptedSessionMessageRow], for sessionId: UUID) -> [EncryptedSessionMessageRow] {
        let normalized = deduplicatedAndSortedRows(rows)
        rowsBySession[sessionId] = normalized
        return normalized
    }

    func cachedRows(for sessionId: UUID) -> [EncryptedSessionMessageRow]? {
        rowsBySession[sessionId]
    }

    func setSessionKey(_ sessionKey: Data, for sessionId: UUID) {
        sessionKeyBySession[sessionId] = sessionKey
    }

    func sessionKey(for sessionId: UUID) -> Data? {
        sessionKeyBySession[sessionId]
    }

    func upsert(_ row: EncryptedSessionMessageRow, for sessionId: UUID) -> [EncryptedSessionMessageRow] {
        var rows = rowsBySession[sessionId] ?? []

        if let existingIndex = rows.firstIndex(where: { $0.id == row.id }) {
            rows[existingIndex] = row
        } else {
            rows.append(row)
        }

        let sorted = sortedRows(rows)
        rowsBySession[sessionId] = sorted
        return sorted
    }

    private func deduplicatedAndSortedRows(_ rows: [EncryptedSessionMessageRow]) -> [EncryptedSessionMessageRow] {
        guard rows.count > 1 else { return rows }

        var latestByID: [String: IndexedEncryptedRow] = [:]

        for (index, row) in rows.enumerated() {
            let candidate = IndexedEncryptedRow(row: row, index: index)
            guard let existing = latestByID[row.id] else {
                latestByID[row.id] = candidate
                continue
            }

            if shouldPrefer(candidate, over: existing) {
                latestByID[row.id] = candidate
            }
        }

        return sortedRows(latestByID.values.map(\.row))
    }

    private func shouldPrefer(_ candidate: IndexedEncryptedRow, over existing: IndexedEncryptedRow) -> Bool {
        if candidate.row.sequenceNumber != existing.row.sequenceNumber {
            return candidate.row.sequenceNumber > existing.row.sequenceNumber
        }

        let candidateDate = candidate.row.createdAt ?? .distantPast
        let existingDate = existing.row.createdAt ?? .distantPast
        if candidateDate != existingDate {
            return candidateDate > existingDate
        }

        return candidate.index > existing.index
    }

    private func sortedRows(_ rows: [EncryptedSessionMessageRow]) -> [EncryptedSessionMessageRow] {
        rows.sorted { lhs, rhs in
            if lhs.sequenceNumber != rhs.sequenceNumber {
                return lhs.sequenceNumber < rhs.sequenceNumber
            }

            let lhsDate = lhs.createdAt ?? .distantPast
            let rhsDate = rhs.createdAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }

            return lhs.id < rhs.id
        }
    }
}

private struct IndexedEncryptedRow {
    let row: EncryptedSessionMessageRow
    let index: Int
}
