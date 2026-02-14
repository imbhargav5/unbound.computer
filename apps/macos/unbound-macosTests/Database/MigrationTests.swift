//
//  MigrationTests.swift
//  unbound-macosTests
//
//  Tests for data-model migration compatibility.
//

import Foundation
import XCTest
@testable import unbound_macos

final class MigrationTests: XCTestCase {
    func testLegacyProjectsStoreMigratesToRepositoriesStore() throws {
        struct LegacyProjectsStore: Codable {
            var projects: [LegacyProject]
            let version: Int
        }
        struct LegacyProject: Codable {
            let id: UUID
            let path: String
            let name: String
            var lastAccessed: Date
            let addedAt: Date
            var isGitRepository: Bool
        }

        let legacyPayload = try JSONEncoder().encode(
            LegacyProjectsStore(
                projects: [
                    LegacyProject(
                        id: UUID(),
                        path: "/tmp/legacy-repo",
                        name: "legacy-repo",
                        lastAccessed: Date(timeIntervalSince1970: 1_708_000_000),
                        addedAt: Date(timeIntervalSince1970: 1_708_000_000),
                        isGitRepository: true
                    ),
                ],
                version: 1
            )
        )

        let migrated = try RepositoriesStore(migratingFrom: legacyPayload)
        XCTAssertEqual(migrated.version, 2)
        XCTAssertEqual(migrated.repositories.count, 1)
        XCTAssertEqual(migrated.repositories[0].name, "legacy-repo")
        XCTAssertEqual(migrated.repositories[0].path, "/tmp/legacy-repo")
        XCTAssertTrue(migrated.repositories[0].isGitRepository)
    }

    func testLegacyProjectsStoreMigrationRejectsInvalidPayload() {
        let invalidPayload = Data("{}".utf8)
        XCTAssertThrowsError(try RepositoriesStore(migratingFrom: invalidPayload))
    }
}
