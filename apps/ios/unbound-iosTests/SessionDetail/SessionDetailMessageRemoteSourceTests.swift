import Foundation
import XCTest

@testable import unbound_ios

final class SessionDetailMessageRemoteSourceTests: XCTestCase {
    func testFetchEncryptedRowsUsesSingleQueryContract() async throws {
        let sessionId = UUID()
        let payload = try JSONSerialization.data(withJSONObject: [[
            "id": 1,
            "sequence_number": 1,
            "created_at": "2026-02-10T00:00:00Z",
            "content_encrypted": Data(repeating: 0x01, count: 20).base64EncodedString(),
            "content_nonce": Data(repeating: 0x02, count: 12).base64EncodedString()
        ]])

        let client = MockSessionDetailSupabaseClient(result: .success(payload))
        let source = SupabaseSessionDetailMessageRemoteSource(supabaseClient: client)

        let rows = try await source.fetchEncryptedRows(sessionId: sessionId)

        XCTAssertEqual(client.calls, 1)
        XCTAssertEqual(client.lastTableName, SupabaseSessionDetailMessageRemoteSource.tableName)
        XCTAssertEqual(client.lastSelectClause, SupabaseSessionDetailMessageRemoteSource.selectClause)
        XCTAssertEqual(client.lastSessionId, sessionId)
        XCTAssertEqual(rows.count, 1)
    }

    func testFetchEncryptedRowsMapsTransportErrors() async {
        let client = MockSessionDetailSupabaseClient(result: .failure(MockSourceError.failed))
        let source = SupabaseSessionDetailMessageRemoteSource(supabaseClient: client)

        do {
            _ = try await source.fetchEncryptedRows(sessionId: UUID())
            XCTFail("Expected fetch failure")
        } catch let error as SessionDetailMessageError {
            XCTAssertEqual(error, .fetchFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private enum MockSourceError: Error {
    case failed
}

private final class MockSessionDetailSupabaseClient: SessionDetailSupabaseQuerying {
    private let result: Result<Data, Error>

    var calls = 0
    var lastSessionId: UUID?
    var lastTableName: String?
    var lastSelectClause: String?

    init(result: Result<Data, Error>) {
        self.result = result
    }

    func fetchEncryptedSessionMessages(
        sessionId: UUID,
        tableName: String,
        selectClause: String
    ) async throws -> Data {
        calls += 1
        lastSessionId = sessionId
        lastTableName = tableName
        lastSelectClause = selectClause
        return try result.get()
    }
}
