import Foundation
import Observation

public struct RawSessionRow: Equatable, Sendable {
    public let id: String
    public let sequenceNumber: Int?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let payload: String

    public init(
        id: String,
        sequenceNumber: Int?,
        createdAt: Date?,
        updatedAt: Date?,
        payload: String
    ) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

public protocol ClaudeSessionMessageSource: Sendable {
    var isDeviceSource: Bool { get }
    func loadInitial(sessionId: UUID) async throws -> [RawSessionRow]
    func stream(sessionId: UUID) -> AsyncThrowingStream<RawSessionRow, Error>
}

@Observable
public final class ClaudeCodingSessionState {
    public private(set) var timeline: [ClaudeConversationTimelineEntry] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var decryptedMessageCount = 0

    private let source: ClaudeSessionMessageSource
    private var sessionId: UUID?
    private var streamTask: Task<Void, Never>?
    private var rowsByCanonicalId: [String: RawSessionRow] = [:]
    private var parser = ClaudeConversationTimelineParser()

    public init(source: ClaudeSessionMessageSource) {
        self.source = source
    }

    public func start(sessionId: UUID) async {
        stop()
        self.sessionId = sessionId
        isLoading = true
        errorMessage = nil

        do {
            let rows = try await source.loadInitial(sessionId: sessionId)
            apply(rows: rows)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await row in source.stream(sessionId: sessionId) {
                    self.apply(rows: [row])
                }
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func reload() async {
        guard let sessionId else { return }
        isLoading = true
        errorMessage = nil

        do {
            let rows = try await source.loadInitial(sessionId: sessionId)
            apply(rows: rows, replaceExisting: true)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        sessionId = nil
        isLoading = false
    }

    public func ingest(rows: [RawSessionRow]) {
        apply(rows: rows)
    }

    public func replace(rows: [RawSessionRow]) {
        apply(rows: rows, replaceExisting: true)
    }

    private func apply(rows: [RawSessionRow], replaceExisting: Bool = false) {
        var didChange = false

        if replaceExisting {
            rowsByCanonicalId.removeAll()
            didChange = true
        }

        for row in rows {
            let canonicalId = canonicalRowId(for: row)
            if let existing = rowsByCanonicalId[canonicalId] {
                if shouldReplace(existing: existing, with: row) {
                    rowsByCanonicalId[canonicalId] = row
                    didChange = true
                }
            } else {
                rowsByCanonicalId[canonicalId] = row
                didChange = true
            }
        }

        guard didChange else { return }
        rebuildTimeline()
    }

    private func rebuildTimeline() {
        let sortedRows = rowsByCanonicalId.values.sorted { lhs, rhs in
            if let lhsSeq = lhs.sequenceNumber, let rhsSeq = rhs.sequenceNumber, lhsSeq != rhsSeq {
                return lhsSeq < rhsSeq
            }
            if let lhsDate = lhs.createdAt, let rhsDate = rhs.createdAt, lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.id < rhs.id
        }

        let newParser = ClaudeConversationTimelineParser()
        for row in sortedRows {
            _ = newParser.ingest(rawJSON: row.payload)
        }

        parser = newParser
        timeline = parser.currentTimeline()
        decryptedMessageCount = rowsByCanonicalId.count
    }

    private func shouldReplace(existing: RawSessionRow, with incoming: RawSessionRow) -> Bool {
        if let existingSeq = existing.sequenceNumber, let incomingSeq = incoming.sequenceNumber,
           existingSeq != incomingSeq {
            return incomingSeq > existingSeq
        }
        if let existingDate = existing.updatedAt ?? existing.createdAt,
           let incomingDate = incoming.updatedAt ?? incoming.createdAt,
           existingDate != incomingDate {
            return incomingDate > existingDate
        }
        return incoming.id != existing.id
    }

    private func canonicalRowId(for row: RawSessionRow) -> String {
        guard let data = row.payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return row.id
        }

        let resolved = resolveRawJSON(from: json)
        if let message = resolved["message"] as? [String: Any],
           let messageId = message["id"] as? String {
            return messageId
        }
        if let id = resolved["id"] as? String {
            return id
        }
        if let eventId = resolved["event_id"] as? String {
            return eventId
        }
        return row.id
    }

    private func resolveRawJSON(from payload: [String: Any]) -> [String: Any] {
        var current = payload
        var depth = 0
        while depth < 4,
              let wrappedRawJSON = current["raw_json"] as? String,
              let wrappedData = wrappedRawJSON.data(using: .utf8),
              let wrappedPayload = try? JSONSerialization.jsonObject(with: wrappedData) as? [String: Any] {
            current = wrappedPayload
            depth += 1
        }
        return current
    }
}
