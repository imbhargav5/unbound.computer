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
    private static let protocolTypes: Set<String> = [
        "assistant", "mcq_response_command", "output_chunk", "result", "stream_event",
        "streaming_generating", "streaming_thinking", "system", "terminal_output",
        "tool_result", "user", "user_confirmation_command", "user_prompt_command"
    ]
    private static let toolEnvelopeBlockTypes: Set<String> = ["tool_result", "tool_use"]
    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601PlainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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
            if let payload = decodedJSONPayload(from: row.payload) {
                let enrichedPayload = payloadWithRowMetadata(payload, row: row)
                _ = newParser.ingest(payload: enrichedPayload)
                continue
            }

            if shouldSynthesizeUserPlaintext(row.payload),
               let fallbackPayload = synthesizedUserPayload(from: row) {
                _ = newParser.ingest(payload: fallbackPayload)
            }
        }

        parser = newParser
        timeline = parser.currentTimeline()
        decryptedMessageCount = rowsByCanonicalId.count
    }

    private func payloadWithRowMetadata(_ payload: [String: Any], row: RawSessionRow) -> [String: Any] {
        var enriched = payload

        if parseInteger(enriched["sequence_number"]) == nil, parseInteger(enriched["sequence"]) == nil,
           let sequenceNumber = row.sequenceNumber {
            enriched["sequence_number"] = sequenceNumber
        }

        if parseDate(enriched["created_at"]) == nil {
            if let createdAt = row.createdAt {
                enriched["created_at"] = ISO8601DateFormatter().string(from: createdAt)
            } else if let updatedAt = row.updatedAt {
                enriched["created_at"] = ISO8601DateFormatter().string(from: updatedAt)
            }
        }

        if !hasStablePayloadIdentity(enriched) {
            enriched["id"] = row.id
        }

        return enriched
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
        guard let json = decodedJSONPayload(from: row.payload) else {
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

    private func decodedJSONPayload(from raw: String) -> [String: Any]? {
        var currentRaw = raw
        var depth = 0

        while depth < 4 {
            guard let data = currentRaw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }

            if let payload = json as? [String: Any] {
                return payload
            }

            guard let wrapped = json as? String else {
                return nil
            }

            currentRaw = wrapped
            depth += 1
        }

        return nil
    }

    private func shouldSynthesizeUserPlaintext(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !looksLikeSerializedProtocolEnvelope(trimmed)
    }

    private func looksLikeSerializedProtocolEnvelope(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else {
            return false
        }

        if let payload = decodedJSONPayload(from: trimmed) {
            return isProtocolEnvelopePayload(payload)
        }

        let normalized = trimmed.lowercased()
        if Self.protocolTypes.contains(where: { normalized.contains("\"type\":\"\($0)\"") }) {
            return true
        }

        let hasTypeMarker = normalized.contains("\"type\"")
        let hasToolMarkers = normalized.contains("\"tool_use\"")
            || normalized.contains("\"tool_result\"")
            || normalized.contains("\"tool_use_id\"")
            || normalized.contains("\"raw_json\"")
        return hasTypeMarker && hasToolMarkers
    }

    private func isProtocolEnvelopePayload(_ payload: [String: Any]) -> Bool {
        let resolved = resolveRawJSON(from: payload)

        if resolved["raw_json"] as? String != nil {
            return true
        }

        if let type = (resolved["type"] as? String)?.lowercased(),
           Self.protocolTypes.contains(type) {
            return true
        }

        if let message = resolved["message"] as? [String: Any],
           let contentBlocks = message["content"] as? [[String: Any]] {
            return contentBlocks.contains { block in
                guard let blockType = (block["type"] as? String)?.lowercased() else {
                    return false
                }
                return Self.toolEnvelopeBlockTypes.contains(blockType)
            }
        }

        return false
    }

    private func synthesizedUserPayload(from row: RawSessionRow) -> [String: Any]? {
        let trimmedText = row.payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        var payload: [String: Any] = [
            "id": row.id,
            "type": "user_prompt_command",
            "message": trimmedText
        ]

        if let sequenceNumber = row.sequenceNumber {
            payload["sequence_number"] = sequenceNumber
        }

        if let createdAt = row.createdAt {
            payload["created_at"] = ISO8601DateFormatter().string(from: createdAt)
        }

        return payload
    }

    private func parseInteger(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let stringValue = value as? String {
            return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func parseDate(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let timestamp = value as? TimeInterval {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let dateString = value as? String {
            let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Self.iso8601FractionalFormatter.date(from: trimmed)
                ?? Self.iso8601PlainFormatter.date(from: trimmed) {
                return parsed
            }
            if let seconds = TimeInterval(trimmed) {
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }

    private func hasStablePayloadIdentity(_ payload: [String: Any]) -> Bool {
        if let message = payload["message"] as? [String: Any],
           let messageId = message["id"] as? String,
           !messageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let id = payload["id"] as? String,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let eventId = payload["event_id"] as? String,
           !eventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        return false
    }
}
