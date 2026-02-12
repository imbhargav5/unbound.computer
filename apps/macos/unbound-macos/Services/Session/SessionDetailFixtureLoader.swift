//
//  SessionDetailFixtureLoader.swift
//  unbound-macos
//
//  Fixture-backed loader for Session Detail Xcode previews and tests.
//

import Foundation

struct SessionDetailFixture: Decodable {
    struct Metadata: Decodable {
        let sourceDBPath: String
        let exportedAt: Date
        let selectedSessionId: String
        let selectedMessageCount: Int

        enum CodingKeys: String, CodingKey {
            case sourceDBPath = "source_db_path"
            case exportedAt = "exported_at"
            case selectedSessionId = "selected_session_id"
            case selectedMessageCount = "selected_message_count"
        }
    }

    struct Session: Decodable {
        let id: String
        let title: String
        let status: String
        let createdAt: Date
        let lastAccessedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, status
            case createdAt = "created_at"
            case lastAccessedAt = "last_accessed_at"
        }
    }

    struct MessageRow: Decodable {
        let id: String
        let sequenceNumber: Int
        let timestamp: String
        let content: String

        enum CodingKeys: String, CodingKey {
            case id, timestamp, content
            case sequenceNumber = "sequence_number"
        }
    }

    let metadata: Metadata
    let session: Session
    let messages: [MessageRow]
}

enum SessionDetailFixtureLoaderError: Error, LocalizedError {
    case fixtureNotFound(String)
    case fixtureDecodeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .fixtureNotFound(let fixturePath):
            return "Session detail fixture not found at \(fixturePath)"
        case .fixtureDecodeFailed(let error):
            return "Failed to decode session detail fixture: \(error.localizedDescription)"
        }
    }
}

struct SessionDetailPreviewData {
    let session: Session
    let rawMessageCount: Int
    let parsedMessages: [ChatMessage]
}

final class SessionDetailFixtureLoader {
    static let previewRepositoryId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private let fixtureURL: URL
    private let decoder: JSONDecoder

    init(fixtureURL: URL) {
        self.fixtureURL = fixtureURL
        self.decoder = Self.makeDecoder()
    }

    convenience init(
        resourceName: String = "session-detail-max-messages",
        bundle: Bundle = .main
    ) throws {
        let candidateSubdirectories: [String?] = [
            "PreviewFixtures",
            "Resources/PreviewFixtures",
            nil,
        ]

        guard let fixtureURL = candidateSubdirectories.compactMap({
            bundle.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: $0
            )
        }).first else {
            throw SessionDetailFixtureLoaderError.fixtureNotFound(
                "PreviewFixtures/\(resourceName).json (also checked Resources/PreviewFixtures)"
            )
        }

        self.init(fixtureURL: fixtureURL)
    }

    func loadFixture() throws -> SessionDetailFixture {
        do {
            let data = try Data(contentsOf: fixtureURL)
            return try decoder.decode(SessionDetailFixture.self, from: data)
        } catch let error as SessionDetailFixtureLoaderError {
            throw error
        } catch {
            throw SessionDetailFixtureLoaderError.fixtureDecodeFailed(error)
        }
    }

    func loadParsedMessages() throws -> [ChatMessage] {
        let fixture = try loadFixture()
        return parseMessages(from: fixture)
    }

    func loadSession(repositoryId: UUID = SessionDetailFixtureLoader.previewRepositoryId) throws -> Session {
        let fixture = try loadFixture()
        return Self.mapSession(fixture.session, repositoryId: repositoryId)
    }

    func loadPreviewData(repositoryId: UUID = SessionDetailFixtureLoader.previewRepositoryId) throws -> SessionDetailPreviewData {
        let fixture = try loadFixture()
        let parsedMessages = parseMessages(from: fixture)

        return SessionDetailPreviewData(
            session: Self.mapSession(fixture.session, repositoryId: repositoryId),
            rawMessageCount: fixture.messages.count,
            parsedMessages: parsedMessages
        )
    }

    static func mapSession(
        _ fixtureSession: SessionDetailFixture.Session,
        repositoryId: UUID = previewRepositoryId
    ) -> Session {
        Session(
            id: UUID(uuidString: fixtureSession.id) ?? UUID(),
            repositoryId: repositoryId,
            title: fixtureSession.title,
            status: mapStatus(fixtureSession.status),
            isWorktree: false,
            worktreePath: nil,
            createdAt: fixtureSession.createdAt,
            lastAccessed: fixtureSession.lastAccessedAt
        )
    }

    static func mapStatus(_ rawStatus: String) -> SessionStatus {
        SessionStatus(rawValue: rawStatus.lowercased()) ?? .active
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(value)"
            )
        }

        return decoder
    }

    private func parseMessages(from fixture: SessionDetailFixture) -> [ChatMessage] {
        let daemonMessages = fixture.messages
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .map { row in
                DaemonMessage(
                    id: row.id,
                    sessionId: fixture.session.id,
                    content: row.content,
                    sequenceNumber: row.sequenceNumber,
                    timestamp: row.timestamp,
                    isStreaming: nil
                )
            }

        let parsed = daemonMessages.compactMap { ClaudeMessageParser.parseMessage($0) }
        return ChatMessageGrouper.groupSubAgentTools(messages: parsed)
    }
}
