//
//  RepositoryRepositoryTests.swift
//  unbound-macosTests
//
//  Repository model behavior tests for daemon-backed persistence.
//

import Foundation
import XCTest
@testable import unbound_macos

final class RepositoryRepositoryTests: XCTestCase {
    func testRepositoryDefaultNameComesFromPath() {
        let repository = Repository(path: "/tmp/unbound-repo")
        XCTAssertEqual(repository.name, "unbound-repo")
    }

    func testRepositoryDisplayPathAbbreviatesHomeDirectory() {
        let home = NSHomeDirectory()
        let repository = Repository(path: "\(home)/Code/unbound")

        let displayPath = repository.displayPath
        XCTAssertTrue(displayPath.hasPrefix("~"), "Expected home-abbreviated display path")
        XCTAssertTrue(displayPath.contains("Code/unbound"))
    }

    func testRepositoryExistsTracksDirectoryLifecycle() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )

        let repository = Repository(path: tempDirectory.path)
        XCTAssertTrue(repository.exists)

        try FileManager.default.removeItem(at: tempDirectory)
        XCTAssertFalse(repository.exists)
    }

    func testDisplaySessionsPathAbbreviatesHomeDirectory() {
        let home = NSHomeDirectory()
        let repository = Repository(
            path: "/tmp/unbound",
            sessionsPath: "\(home)/.unbound/sessions"
        )

        XCTAssertEqual(repository.displaySessionsPath, "~/.unbound/sessions")
    }
}
