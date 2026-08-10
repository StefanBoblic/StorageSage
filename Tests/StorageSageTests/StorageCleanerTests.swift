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
        let progressRecorder = ProgressRecorder()

        let report = cleaner.clean([candidate]) { progressRecorder.record($0) }

        XCTAssertTrue(report.isDryRun)
        XCTAssertEqual(report.previewedCount, 1)
        XCTAssertEqual(report.estimatedReclaimable, candidate.size)
        XCTAssertEqual(report.removedCount, 0)
        XCTAssertEqual(report.estimatedTrashBytes, candidate.size)
        XCTAssertEqual(report.estimatedImmediateDeletionBytes, 0)
        XCTAssertEqual(progressRecorder.values.last?.processedBytes, candidate.size)
        XCTAssertEqual(progressRecorder.values.last?.eligibleBytes, candidate.size)
        XCTAssertEqual(progressRecorder.values.last?.fractionCompleted, 1)
    }

    func testDryRunSeparatesTrashAndImmediateDeletionBytes() {
        let trashCandidate = makeCandidate(
            url: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/example", isDirectory: true)
        )
        let simulatorCandidate = CleanupCandidate(
            id: "orphaned-simulators",
            name: "Unavailable Simulator Devices",
            detail: "Test",
            path: "/virtual/simulators",
            category: .simulators,
            safety: .safe,
            strategy: .deleteUnavailableSimulators,
            size: 2_048,
            modifiedAt: nil
        )
        let cleaner = StorageCleaner(
            policy: AllowPolicy(),
            configuration: DryRunConfiguration(),
            processGuard: OpenProcessGuard(),
            commands: NoopCommands()
        )

        let report = cleaner.clean([trashCandidate, simulatorCandidate]) { _ in }

        XCTAssertEqual(report.estimatedReclaimable, 3_072)
        XCTAssertEqual(report.estimatedTrashBytes, 1_024)
        XCTAssertEqual(report.estimatedImmediateDeletionBytes, 2_048)
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

    func testDeletionPolicyAllowsOnlyExplicitlyReviewedFilesInPersonalFolders() throws {
        let downloads = try XCTUnwrap(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        let url = downloads.appendingPathComponent("old-installer.dmg")
        let regularCandidate = makeCandidate(url: url)
        let reviewedCandidate = CleanupCandidate(
            id: url.path,
            name: "old-installer.dmg",
            detail: "Reviewed",
            path: url.path,
            category: .installers,
            safety: .review,
            strategy: .trashReviewedFile(url),
            size: 1_024,
            modifiedAt: nil
        )

        XCTAssertNotEqual(DefaultDeletionPolicy(whitelist: EmptyWhitelist()).evaluate(regularCandidate), .allowed)
        XCTAssertEqual(DefaultDeletionPolicy(whitelist: EmptyWhitelist()).evaluate(reviewedCandidate), .allowed)
    }

    func testCleanupReportsActualIncreaseInAvailableSpace() {
        let candidate = CleanupCandidate(
            id: "simulators",
            name: "Unavailable Simulator Devices",
            detail: "Test",
            path: "/virtual/simulators",
            category: .simulators,
            safety: .safe,
            strategy: .deleteUnavailableSimulators,
            size: 3_000,
            modifiedAt: nil
        )
        let cleaner = StorageCleaner(
            policy: AllowPolicy(),
            configuration: LiveConfiguration(),
            processGuard: OpenProcessGuard(),
            commands: SuccessfulCommands(),
            volumeSpace: SequencedVolumeSpace(values: [10_000, 12_500])
        )

        let report = cleaner.clean([candidate]) { _ in }

        XCTAssertEqual(report.availableBytesBefore, 10_000)
        XCTAssertEqual(report.availableBytesAfter, 12_500)
        XCTAssertEqual(report.actualFreedBytes, 2_500)
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

private struct LiveConfiguration: CleanupConfigurationProviding {
    var isDryRunEnabled: Bool { false }
}

private struct OpenProcessGuard: CleanupProcessGuarding {
    func blockingReason(for candidate: CleanupCandidate) -> String? { nil }
}

private struct NoopCommands: CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult? { nil }
}

private struct SuccessfulCommands: CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult? {
        CommandResult(output: Data(), errorOutput: Data(), terminationStatus: 0)
    }
}

private final class SequencedVolumeSpace: VolumeSpaceMeasuring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int64]

    init(values: [Int64]) {
        self.values = values
    }

    func availableBytes() -> Int64? {
        lock.withLock {
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }
}

private struct EmptyWhitelist: WhitelistProviding {
    func whitelistedURLs() -> [URL] { [] }
}

private struct FixedWhitelist: WhitelistProviding {
    let url: URL
    func whitelistedURLs() -> [URL] { [url] }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CleanupProgress] = []

    var values: [CleanupProgress] {
        lock.withLock { storage }
    }

    func record(_ progress: CleanupProgress) {
        lock.withLock { storage.append(progress) }
    }
}
