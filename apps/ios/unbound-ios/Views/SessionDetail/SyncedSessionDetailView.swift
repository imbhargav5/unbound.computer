import CryptoKit
import Foundation
import Logging
import PostgREST
import Supabase
import SwiftUI

private let logger = Logger(label: "app.ui.session-detail")

struct SyncedSessionDetailView: View {
    let session: SyncedSession

    @State private var viewModel: SyncedSessionDetailViewModel

    init(session: SyncedSession) {
        self.session = session
        _viewModel = State(initialValue: SyncedSessionDetailViewModel(session: session))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.messages.isEmpty {
                errorView(errorMessage: errorMessage)
            } else if viewModel.messages.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .background(AppTheme.backgroundPrimary)
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.loadMessages(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .task {
            await viewModel.loadMessages()
        }
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingM) {
                headerCard

                LazyVStack(spacing: AppTheme.spacingS) {
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                    }
                }
            }
            .padding(.top, AppTheme.spacingM)
            .padding(.bottom, AppTheme.spacingXL)
        }
        .refreshable {
            await viewModel.loadMessages(force: true)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            Text("Session ID")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Text(session.id.uuidString)
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: AppTheme.spacingM) {
                Label("\(viewModel.messages.count) messages", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                if viewModel.decryptedMessageCount > 0 {
                    Label("\(viewModel.decryptedMessageCount) decrypted", systemImage: "lock.open")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacingM)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, AppTheme.spacingM)
    }

    private var loadingView: some View {
        VStack(spacing: AppTheme.spacingM) {
            ProgressView()
            Text("Loading and decrypting session messages...")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(errorMessage: String) -> some View {
        VStack(spacing: AppTheme.spacingM) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)

            Text("Failed to load session")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingXL)

            Button("Retry") {
                Task {
                    await viewModel.loadMessages(force: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        EmptyStateView(
            icon: "text.bubble",
            title: "No Messages",
            message: "This session has no messages yet."
        )
    }
}

@MainActor
@Observable
final class SyncedSessionDetailViewModel {
    private let session: SyncedSession
    private let authService: AuthService
    private let viewerService: CodingSessionViewerService

    private(set) var messages: [Message] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var decryptedMessageCount = 0

    private var hasLoaded = false

    init(
        session: SyncedSession,
        authService: AuthService = .shared,
        viewerService: CodingSessionViewerService = CodingSessionViewerService()
    ) {
        self.session = session
        self.authService = authService
        self.viewerService = viewerService
    }

    func loadMessages(force: Bool = false) async {
        if isLoading {
            return
        }
        if hasLoaded && !force {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let payload = try await fetchMessagePayload()
            let rows = try SupabaseSessionMessageRow.parseRows(from: payload)

            let requiresDecryption = rows.contains {
                $0.contentEncrypted != nil && $0.contentNonce != nil
            }

            var sessionKey: Data?
            if requiresDecryption {
                let sessionSecret = try await viewerService.joinCodingSession(session.id)
                sessionKey = try SessionSecretKeyParser.parse(secret: sessionSecret)
            }

            var decryptedCount = 0
            let mapped = try rows.map { row in
                let plaintext = try row.resolvePlaintext(sessionKey: sessionKey)
                if row.contentEncrypted != nil && row.contentNonce != nil {
                    decryptedCount += 1
                }

                return Message(
                    id: row.stableUUID,
                    content: MessagePayloadParser.displayText(from: plaintext),
                    role: MessagePayloadParser.role(from: plaintext, fallback: row.role),
                    timestamp: row.createdAt ?? Date(),
                    isStreaming: false
                )
            }

            messages = mapped.sorted { $0.timestamp < $1.timestamp }
            decryptedMessageCount = decryptedCount
        } catch {
            logger.error("Failed to load/decrypt session \(self.session.id): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func fetchMessagePayload() async throws -> Data {
        let tableNames = [
            "agent_coding_session_messages",
            "conversation_events"
        ]

        let selectClauses = [
            "id, sequence_number, created_at, content_encrypted, content_nonce, content, role",
            "id, sequence_number, created_at, content_encrypted, content_nonce, role",
            "id, sequence_number, created_at, content_encrypted, content_nonce, content",
            "id, sequence_number, created_at, content_encrypted, content_nonce",
            "id, sequence_number, created_at, content, role",
            "id, sequence_number, created_at, content"
        ]

        var lastError: Error?

        for tableName in tableNames {
            for selectClause in selectClauses {
                do {
                    let response = try await authService.supabaseClient
                        .from(tableName)
                        .select(selectClause)
                        .eq("session_id", value: session.id.uuidString)
                        .order("sequence_number", ascending: true)
                        .execute()
                    return response.data
                } catch {
                    lastError = error
                }
            }
        }

        throw lastError ?? NSError(
            domain: "SyncedSessionDetailViewModel",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to fetch session messages from Supabase"]
        )
    }
}

private struct SupabaseSessionMessageRow {
    let id: String
    let sequenceNumber: Int
    let createdAt: Date?
    let contentEncrypted: String?
    let contentNonce: String?
    let content: String?
    let role: Message.MessageRole?

    var stableUUID: UUID {
        if let uuid = UUID(uuidString: id) {
            return uuid
        }

        let digest = SHA256.hash(data: Data("\(id)-\(sequenceNumber)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func resolvePlaintext(sessionKey: Data?) throws -> String {
        if let content, !content.isEmpty {
            return content
        }

        guard let contentEncrypted, let contentNonce else {
            throw NSError(
                domain: "SupabaseSessionMessageRow",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Message payload is missing content"]
            )
        }

        guard let sessionKey else {
            throw NSError(
                domain: "SupabaseSessionMessageRow",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Session decryption key is unavailable"]
            )
        }

        return try Self.decrypt(
            contentEncrypted: contentEncrypted,
            contentNonce: contentNonce,
            sessionKey: sessionKey
        )
    }

    static func parseRows(from data: Data) throws -> [SupabaseSessionMessageRow] {
        guard let rawRows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return rawRows.map { row in
            let id = stringValue(row["id"]) ?? UUID().uuidString
            let sequenceNumber = intValue(row["sequence_number"]) ?? 0
            let createdAt = dateValue(row["created_at"])
            let contentEncrypted = stringValue(row["content_encrypted"])
            let contentNonce = stringValue(row["content_nonce"])
            let content = stringValue(row["content"])
            let role = stringValue(row["role"]).flatMap {
                Message.MessageRole(rawValue: $0.lowercased())
            }

            return SupabaseSessionMessageRow(
                id: id,
                sequenceNumber: sequenceNumber,
                createdAt: createdAt,
                contentEncrypted: contentEncrypted,
                contentNonce: contentNonce,
                content: content,
                role: role
            )
        }
    }

    private static func decrypt(
        contentEncrypted: String,
        contentNonce: String,
        sessionKey: Data
    ) throws -> String {
        guard let ciphertextAndTag = Data(base64Encoded: contentEncrypted) else {
            throw NSError(
                domain: "SupabaseSessionMessageRow",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid base64 ciphertext payload"]
            )
        }
        guard let nonceData = Data(base64Encoded: contentNonce), nonceData.count == 12 else {
            throw NSError(
                domain: "SupabaseSessionMessageRow",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid nonce payload"]
            )
        }
        guard ciphertextAndTag.count >= 16 else {
            throw NSError(
                domain: "SupabaseSessionMessageRow",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Ciphertext payload is too short"]
            )
        }

        let ciphertext = ciphertextAndTag.dropLast(16)
        let tag = ciphertextAndTag.suffix(16)
        let key = SymmetricKey(data: sessionKey)
        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        let plaintextData = try ChaChaPoly.open(sealedBox, using: key)

        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw NSError(
                domain: "SupabaseSessionMessageRow",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Decrypted payload is not valid UTF-8"]
            )
        }

        return plaintext
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let dateString = value as? String else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}

private enum SessionSecretKeyParser {
    static func parse(secret: String) throws -> Data {
        guard secret.hasPrefix("sess_") else {
            throw NSError(
                domain: "SessionSecretKeyParser",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid session secret format"]
            )
        }

        let base64Url = String(secret.dropFirst(5))
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        switch base64.count % 4 {
        case 2:
            base64 += "=="
        case 3:
            base64 += "="
        default:
            break
        }

        guard let keyData = Data(base64Encoded: base64), keyData.count == 32 else {
            throw NSError(
                domain: "SessionSecretKeyParser",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Session secret key is malformed"]
            )
        }

        return keyData
    }
}

private enum MessagePayloadParser {
    static func role(from plaintext: String, fallback: Message.MessageRole?) -> Message.MessageRole {
        guard let payload = jsonPayload(from: plaintext) else {
            return fallback ?? .system
        }

        if let rawRole = payload["role"] as? String,
           let parsedRole = Message.MessageRole(rawValue: rawRole.lowercased()) {
            return parsedRole
        }

        if let wrappedRawJSON = payload["raw_json"] as? String {
            return role(from: wrappedRawJSON, fallback: fallback)
        }

        if let type = payload["type"] as? String {
            switch type.lowercased() {
            case "user", "user_prompt_command", "user_confirmation_command", "mcq_response_command":
                return .user
            case "assistant", "result", "output_chunk", "streaming_thinking", "streaming_generating":
                return .assistant
            default:
                return fallback ?? .system
            }
        }

        return fallback ?? .system
    }

    static func displayText(from plaintext: String) -> String {
        guard let payload = jsonPayload(from: plaintext) else {
            return plaintext
        }

        if let wrappedRawJSON = payload["raw_json"] as? String {
            return displayText(from: wrappedRawJSON)
        }

        if let text = payload["text"] as? String, !text.isEmpty {
            return text
        }

        if let message = payload["message"] as? String, !message.isEmpty {
            return message
        }

        if let content = payload["content"] as? String, !content.isEmpty {
            return content
        }

        if let content = payload["content"] {
            let fragments = textFragments(from: content)
            if !fragments.isEmpty {
                return fragments.joined(separator: "\n")
            }
        }

        if let type = payload["type"] as? String,
           type.lowercased() == "terminal_output",
           let stream = payload["stream"] as? String,
           let content = payload["content"] as? String {
            return "[\(stream)] \(content)"
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let compact = String(data: data, encoding: .utf8) {
            return compact
        }

        return plaintext
    }

    private static func jsonPayload(from plaintext: String) -> [String: Any]? {
        guard let data = plaintext.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let payload = jsonObject as? [String: Any] else {
            return nil
        }
        return payload
    }

    private static func textFragments(from value: Any) -> [String] {
        if let text = value as? String {
            return text.isEmpty ? [] : [text]
        }

        if let array = value as? [Any] {
            return array.flatMap { item in
                if let text = item as? String {
                    return text.isEmpty ? [] : [text]
                }
                if let dict = item as? [String: Any] {
                    if let text = dict["text"] as? String, !text.isEmpty {
                        return [text]
                    }
                    if let content = dict["content"] as? String, !content.isEmpty {
                        return [content]
                    }
                }
                return []
            }
        }

        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String, !text.isEmpty {
                return [text]
            }
            if let content = dict["content"] as? String, !content.isEmpty {
                return [content]
            }
        }

        return []
    }
}
