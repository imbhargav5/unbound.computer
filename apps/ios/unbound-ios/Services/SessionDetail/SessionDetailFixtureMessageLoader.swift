//
//  SessionDetailFixtureMessageLoader.swift
//  unbound-ios
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
        let timestamp: Date
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

final class SessionDetailFixtureMessageLoader: SessionDetailMessageLoading {
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

    func loadMessages(sessionId _: UUID) async throws -> SessionDetailLoadResult {
        let fixture = try loadFixture()
        let rows = fixture.messages.map { message in
            SessionDetailPlaintextMessageRow(
                id: message.id,
                sequenceNumber: message.sequenceNumber,
                createdAt: message.timestamp,
                content: message.content
            )
        }
        return SessionDetailMessageMapper.mapRows(
            rows,
            totalMessageCount: fixture.messages.count
        )
    }

    func messageUpdates(sessionId _: UUID) -> AsyncThrowingStream<SessionDetailLoadResult, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
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
}
