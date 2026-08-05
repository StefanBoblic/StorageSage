//
//  StorageCleanerTests.swift
//  StorageSage
//
//  Created by Stefan Boblic on 05.08.2026.
//

import Foundation
import XCTest
@testable import StorageSage

final class StorageCleanerTests: XCTestCase {
    func testDryRunReportsSpaceWithoutChangingFiles() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/example", isDirectory: true)
        let candidate = makeCandidate(url: directory)
        let cleaner = StorageCleaner(
            policy: AllowPolicy(),
            configuration: DryRunConfiguration(),
            processGuard: OpenProcessGuard(),
            commands: NoopCommands()
        )

        let report = cleaner.clean([candidate])

        XCTAssertTrue(report.isDryRun)
        XCTAssertEqual(report.previewedCount, 1)
        XCTAssertEqual(report.estimatedReclaimable, candidate.size)
        XCTAssertEqual(report.removedCount, 0)
    }

    func testDeletionPolicyRejectsSensitiveUserDirectory() throws {
        let documents = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        let candidate = makeCandidate(
            url: documents.appendingPathComponent("important", isDirectory: true)
        )

        XCTAssertEqual(
            DefaultDeletionPolicy(whitelist: EmptyWhitelist()).evaluate(candidate),
            .denied("StorageSage protects this location from deletion.")
        )
    }

    func testDeletionPolicyHonorsWhitelistAncestors() {
        let caches = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
        let candidate = makeCandidate(
            url: caches.appendingPathComponent("example/child", isDirectory: true)
        )

        XCTAssertEqual(
            DefaultDeletionPolicy(whitelist: FixedWhitelist(url: caches)).evaluate(candidate),
            .denied("The item is protected by your whitelist.")
        )
    }

    private func makeCandidate(url: URL) -> CleanupCandidate {
        CleanupCandidate(
            id: url.path,
            name: "Test Cache",
            detail: "Test",
            path: url.path,
            category: .caches,
            safety: .safe,
            strategy: .trash(url),
            size: 1_024,
            modifiedAt: nil
        )
    }
}

private struct AllowPolicy: DeletionPolicyEvaluating {
    func evaluate(_ candidate: CleanupCandidate) -> DeletionDecision { .allowed }
}

private struct DryRunConfiguration: CleanupConfigurationProviding {
    var isDryRunEnabled: Bool { true }
}

private struct OpenProcessGuard: CleanupProcessGuarding {
    func blockingReason(for candidate: CleanupCandidate) -> String? { nil }
}

private struct NoopCommands: CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult? { nil }
}

private struct EmptyWhitelist: WhitelistProviding {
    func whitelistedURLs() -> [URL] { [] }
}

private struct FixedWhitelist: WhitelistProviding {
    let url: URL
    func whitelistedURLs() -> [URL] { [url] }
}
