import Foundation
import XCTest

@testable import unbound_ios

final class SessionDetailLegacyReferenceTests: XCTestCase {
    func testSessionDetailRuntimeCodeDoesNotReferenceConversationEvents() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SessionDetailLegacyReferenceTests.swift
            .deletingLastPathComponent() // SessionDetail
            .deletingLastPathComponent() // unbound-iosTests

        let paths = [
            root.appendingPathComponent("unbound-ios/Views/SessionDetail/SyncedSessionDetailView.swift").path,
            root.appendingPathComponent("unbound-ios/ViewModels/SessionDetail/SyncedSessionDetailViewModel.swift").path,
            root.appendingPathComponent("unbound-ios/Services/SessionDetail/SessionDetailMessageService.swift").path,
            root.appendingPathComponent("unbound-ios/Services/SessionDetail/SessionDetailMessageRemoteSource.swift").path,
            root.appendingPathComponent("unbound-ios/Services/SessionDetail/EncryptedSessionMessageDecoder.swift").path,
            root.appendingPathComponent("unbound-ios/Services/SessionDetail/SessionMessagePayloadParser.swift").path
        ]

        for path in paths {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertFalse(
                contents.contains("conversation_events"),
                "Found legacy table reference in \(path)"
            )
        }
    }
}
